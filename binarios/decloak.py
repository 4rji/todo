#!/usr/bin/env python3
# 4rji Decloaking Utility - Version 1.1
# Based on Sandfly Security's file decloaking concept (MIT)

import argparse
import hashlib
import mmap
import multiprocessing
import os
import pwd
import shutil
import signal
import stat
import sys
from datetime import datetime

VERSION = "1.1"
CHUNK_SIZE = 1024 * 1024
PREVIEW_BYTES = 256
READ_TIMEOUT = 30

DEFAULT_TARGETS = [
    "/etc",
    "/var/spool/cron",
    "/etc/cron.d",
    "/etc/cron.daily",
    "/etc/cron.hourly",
    "/etc/cron.weekly",
    "/etc/cron.monthly",
    "/root",
]

DEFAULT_FILES_HINT = [
    "/etc/passwd",
    "/etc/shadow",
    "/etc/group",
    "/etc/ld.so.preload",
    "/etc/modules",
    "/etc/crontab",
    "/etc/ssh/sshd_config",
]

SKIP_DIRS = {"/proc", "/sys", "/dev", "/run"}


def positive_int(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def make_parser():
    parser = argparse.ArgumentParser(
        description="Compare standard I/O and mmap contents for possible hidden data.",
        epilog="Exit codes: 0=complete, 1=suspicious files, 2=incomplete/error, 130=interrupted.",
    )
    parser.add_argument("target", nargs="?", help="file or directory (default: system directories)")
    parser.add_argument("-y", "--yes", action="store_true", help="skip the scan confirmation")
    parser.add_argument("-o", "--output", help="new report path (existing files are never overwritten)")
    parser.add_argument("--max-size", type=positive_int, default=50, metavar="MIB",
                        help="maximum file size in MiB, including explicit files (default: 50)")
    parser.add_argument("--show-content", action="store_true",
                        help="include the first 256 bytes of suspicious views; may expose secrets")
    parser.add_argument("--no-sudo", action="store_true", help="scan with current privileges")
    return parser


def ensure_root(args):
    if os.geteuid() == 0 or args.no_sudo:
        return
    sudo = shutil.which("sudo")
    if sudo is None:
        raise OSError("sudo was not found; run as root or use --no-sudo")
    command = [sudo, "--", sys.executable, "-I", os.path.realpath(__file__),
               "--max-size", str(args.max_size)]
    if args.yes:
        command.append("--yes")
    if args.output:
        command.extend(["--output", args.output])
    if args.show_content:
        command.append("--show-content")
    if args.target:
        command.extend(["--", args.target])
    print("Requesting administrator privileges with sudo...", flush=True)
    os.execv(sudo, command)


def report_owner():
    uid = os.getuid()
    if os.geteuid() == 0 and "SUDO_UID" in os.environ:
        uid = int(os.environ["SUDO_UID"])
    return pwd.getpwuid(uid)


def open_report(path, owner):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    try:
        if os.geteuid() == 0:
            os.fchown(fd, owner.pw_uid, owner.pw_gid)
        os.fchmod(fd, 0o600)
        return os.fdopen(fd, "w", encoding="utf-8", errors="backslashreplace")
    except BaseException:
        os.close(fd)
        raise


def emit(message, report_fp=None):
    print(message)
    if report_fp is not None:
        report_fp.write(message + "\n")
        report_fp.flush()


def should_skip_path(path):
    for candidate in (os.path.abspath(path), os.path.realpath(path)):
        for directory in SKIP_DIRS:
            if candidate == directory or candidate.startswith(directory + os.sep):
                return True
    return False


def fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def read_standard(fp, max_bytes, show_content):
    digest = hashlib.sha256()
    size = 0
    preview = b""
    while True:
        chunk = fp.read(min(CHUNK_SIZE, max_bytes - size + 1))
        if not chunk:
            break
        size += len(chunk)
        if size > max_bytes:
            raise ValueError("file grew beyond the size limit during standard I/O")
        digest.update(chunk)
        if show_content and len(preview) < PREVIEW_BYTES:
            preview += chunk[:PREVIEW_BYTES - len(preview)]
    return {"size": size, "sha256": digest.hexdigest(), "preview": preview}


def read_mmap(fp, size, show_content):
    digest = hashlib.sha256()
    total = 0
    preview = b""
    if size:
        with mmap.mmap(fp.fileno(), size, access=mmap.ACCESS_READ) as mapping:
            for offset in range(0, len(mapping), CHUNK_SIZE):
                chunk = mapping[offset:offset + CHUNK_SIZE]
                digest.update(chunk)
                total += len(chunk)
                if show_content and len(preview) < PREVIEW_BYTES:
                    preview += chunk[:PREVIEW_BYTES - len(preview)]
    return {"size": total, "sha256": digest.hexdigest(), "preview": preview}


def compare_once(path, expected_inode, max_bytes, show_content):
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    with os.fdopen(os.open(path, flags), "rb", buffering=0) as fp:
        before = os.fstat(fp.fileno())
        if not stat.S_ISREG(before.st_mode):
            return {"status": "skipped", "reason": "not a regular file"}
        if (before.st_dev, before.st_ino) != expected_inode:
            return {"status": "changed", "reason": "file replaced before comparison"}
        if before.st_size > max_bytes:
            return {"status": "skipped", "reason": "file exceeds the size limit"}
        standard = read_standard(fp, max_bytes, show_content)
        if fingerprint(before) != fingerprint(os.fstat(fp.fileno())):
            return {"status": "changed", "reason": "file changed during standard I/O"}
        mapped = read_mmap(fp, before.st_size, show_content)
        after = os.fstat(fp.fileno())
        current = os.stat(path, follow_symlinks=False)
        if fingerprint(before) != fingerprint(after) or fingerprint(after) != fingerprint(current):
            return {"status": "changed", "reason": "file changed during comparison"}
    same = (standard["size"], standard["sha256"]) == (mapped["size"], mapped["sha256"])
    return {"status": "matched" if same else "suspicious", "standard": standard,
            "mmap": mapped, "fingerprint": fingerprint(after)}


def inspect_file(path, expected_inode, max_bytes, show_content):
    try:
        result = compare_once(path, expected_inode, max_bytes, show_content)
        if result["status"] != "suspicious":
            return result
        repeated = compare_once(path, expected_inode, max_bytes, show_content)
        if repeated != result:
            return {"status": "changed", "reason": "initial difference was not reproducible"}
        return result
    except FileNotFoundError:
        return {"status": "changed", "reason": "file disappeared during comparison"}
    except ValueError as error:
        return {"status": "changed", "reason": str(error)}
    except OSError as error:
        return {"status": "unreadable", "reason": str(error)}


def comparison_worker(connection):
    # A file truncated during mmap can cause SIGBUS. Keep that crash out of the scanner.
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    import resource
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    try:
        while True:
            request = connection.recv()
            if request is None:
                break
            connection.send(inspect_file(*request))
    except EOFError:
        pass
    finally:
        connection.close()


class Comparator:
    def __init__(self):
        self.connection = None
        self.process = None

    def __enter__(self):
        return self

    def close(self):
        if self.process is not None:
            if self.process.is_alive():
                self.process.terminate()
            self.process.join(timeout=1)
            if self.process.is_alive():
                self.process.kill()
                self.process.join(timeout=1)
            self.process.close()
            self.process = None
        if self.connection is not None:
            self.connection.close()
            self.connection = None

    def __exit__(self, *_):
        self.close()

    def compare(self, path, inode, max_bytes, show_content):
        if self.process is None:
            context = multiprocessing.get_context("spawn")
            connection, child = context.Pipe()
            process = context.Process(target=comparison_worker, args=(child,), daemon=True)
            try:
                process.start()
            except BaseException:
                connection.close()
                raise
            finally:
                child.close()
            self.connection = connection
            self.process = process
        try:
            self.connection.send((path, inode, max_bytes, show_content))
            if self.connection.poll(READ_TIMEOUT):
                return self.connection.recv()
            reason = f"comparison exceeded {READ_TIMEOUT} seconds; result inconclusive"
        except (EOFError, OSError):
            reason = "comparison worker stopped unexpectedly (possible mmap fault); result inconclusive"
        self.close()
        return {"status": "unreadable", "reason": reason}


def iter_files(root, on_error):
    if not os.path.isdir(root):
        yield root
        return
    for directory, names, files in os.walk(root, followlinks=False, onerror=on_error):
        if should_skip_path(directory):
            names[:] = []
            continue
        names[:] = [name for name in names
                    if not should_skip_path(os.path.join(directory, name))
                    and not os.path.islink(os.path.join(directory, name))]
        for name in files:
            yield os.path.join(directory, name)


def show_finding(path, result, report_fp, show_content):
    emit(f"\n[ALERT] Reproducible content difference: {path!r}", report_fp)
    for label in ("standard", "mmap"):
        view = result[label]
        emit(f"  {label}: {view['size']} bytes; SHA-256 {view['sha256']}", report_fp)
        if show_content:
            emit(f"  {label} preview (first {PREVIEW_BYTES} bytes): {view['preview']!r}", report_fp)


def run_scan(targets, args, report_fp):
    counts = dict(matched=0, suspicious=0, unreadable=0, changed=0, skipped=0, duplicates=0)
    findings = []
    report_info = os.fstat(report_fp.fileno())
    seen = {(report_info.st_dev, report_info.st_ino)}
    max_bytes = args.max_size * 1024 * 1024

    def on_error(error):
        counts["unreadable"] += 1
        emit(f"[ERROR] {error}", report_fp)

    interrupted = False
    with Comparator() as comparator:
        try:
            for target in targets:
                if not os.path.lexists(target):
                    emit(f"[SKIP] Default target does not exist: {target!r}", report_fp)
                    continue
                emit(f"\n[+] Scanning: {target!r}", report_fp)
                for path in iter_files(target, on_error):
                    if should_skip_path(path):
                        counts["skipped"] += 1
                        continue
                    try:
                        info = os.lstat(path)
                    except OSError as error:
                        on_error(error)
                        continue
                    if not stat.S_ISREG(info.st_mode):
                        counts["skipped"] += 1
                        continue
                    inode = (info.st_dev, info.st_ino)
                    if inode in seen:
                        counts["duplicates"] += 1
                        continue
                    seen.add(inode)
                    if info.st_size > max_bytes:
                        counts["skipped"] += 1
                        emit(f"[SKIP] Larger than {args.max_size} MiB: {path!r}", report_fp)
                        continue
                    result = comparator.compare(path, inode, max_bytes, args.show_content)
                    status = result["status"]
                    counts[status] += 1
                    if status == "suspicious":
                        findings.append(path)
                        show_finding(path, result, report_fp, args.show_content)
                    elif status != "matched":
                        emit(f"[{status.upper()}] {path!r}: {result['reason']}", report_fp)
                    compared = counts["matched"] + counts["suspicious"]
                    if status in ("matched", "suspicious") and compared % 250 == 0:
                        emit(f"[+] Progress: {compared} stable files compared", report_fp)
        except KeyboardInterrupt:
            interrupted = True
            emit("\nInterrupted; preserving the partial report.", report_fp)

    compared = counts["matched"] + counts["suspicious"]
    emit("\n" + "=" * 60 + "\nScan summary\n" + "=" * 60, report_fp)
    for label, value in (
        ("Stable files compared", compared), ("Suspicious files", counts["suspicious"]),
        ("Unreadable/errors", counts["unreadable"]), ("Changed/inconclusive", counts["changed"]),
        ("Skipped files", counts["skipped"]), ("Duplicate files avoided", counts["duplicates"]),
    ):
        emit(f"{label}: {value}", report_fp)
    if findings:
        emit("Suspicious files:\n" + "\n".join(f"  - {path!r}" for path in findings), report_fp)
        emit("ALERT: Repeated differences found; investigate before concluding a rootkit is present.", report_fp)
    elif interrupted or counts["unreadable"] or counts["changed"] or not compared:
        emit("INCOMPLETE: No confirmed differences; some targets could not be compared reliably.", report_fp)
    else:
        emit("OK: No differences found in compared files, within the scan limits.", report_fp)
    emit("This comparison does not prove the system is free of rootkits.", report_fp)
    if interrupted:
        return 130
    if findings:
        return 1
    return 2 if counts["unreadable"] or counts["changed"] or not compared else 0


def main():
    parser = make_parser()
    args = parser.parse_args()
    # Resolve user-relative paths before sudo changes HOME.
    if args.target:
        args.target = os.path.abspath(os.path.expanduser(args.target))
        if not os.path.lexists(args.target):
            parser.error(f"target does not exist: {args.target!r}")
        if should_skip_path(args.target):
            parser.error("/proc, /sys, /dev and /run are excluded")
    if args.output:
        args.output = os.path.abspath(os.path.expanduser(args.output))
    try:
        ensure_root(args)
        owner = report_owner()
    except (OSError, KeyError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    report_path = args.output or os.path.join(owner.pw_dir, f"ESCANEO_{timestamp}.txt")
    targets = [args.target] if args.target else DEFAULT_TARGETS
    header = [f"4rji Decloaking Utility - Version {VERSION}",
              "Compares byte counts and SHA-256 hashes from standard I/O and read-only mmap.",
              "Repeats differences and checks file metadata to identify changing files.",
              f"File size limit: {args.max_size} MiB; per-file timeout: {READ_TIMEOUT} seconds.",
              f"Report file: {report_path!r} (permissions 0600)",
              "Targets to scan:"] + [f"  - {target!r}" for target in targets]
    if not args.target:
        header += ["High-value file examples:"] + [f"  - {path}" for path in DEFAULT_FILES_HINT]
    header.append("File contents are included only with --show-content.")
    emit("\n".join(header))
    if not args.yes:
        try:
            if input("Continue? [Y/n]: ").strip().lower() not in ("", "y", "yes"):
                print("Cancelled.")
                return 0
        except EOFError:
            print("Cancelled: no confirmation received. Use --yes for unattended scans.")
            return 2
    try:
        with open_report(report_path, owner) as report_fp:
            report_fp.write("\n".join(header) + "\n")
            status = run_scan(targets, args, report_fp)
            emit(f"\nSaved report: {report_path!r}", report_fp)
            return status
    except OSError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nCancelled.", file=sys.stderr)
        sys.exit(130)
