#!/usr/bin/env bash
#
# descargar_dockerlabs.sh - descarga las máquinas de https://dockerlabs.es
#
# Uso:
#   ./descargar_dockerlabs.sh [opciones] [carpeta_destino]     (por defecto ./maquinas)
#
# Opciones:
#   --lista         Muestra las máquinas y sus tamaños, sin descargar nada
#   --solo a,b,c    Descarga solo esas (nombre del archivo sin extensión: nightblade,psycho)
#   --pausa N       Segundos de espera entre descargas (por defecto 3)
#   --forzar        Empieza aunque no haya espacio para todo (para si el disco se llena)
#   -h, --help      Muestra esta ayuda
#
# Cómo funciona:
#   - Descarga de una en una, con pausa, y se detiene si el servidor limita (403/429/503).
#   - Se puede cortar y relanzar cuando quieras: salta lo ya bajado y continúa lo a medias.
#   - Cada archivo se baja como .part y solo recibe su nombre final tras comprobar el
#     tamaño y la integridad. Si la comprobación falla queda como .invalido.
#   - No descomprime ni ejecuta nada de lo que baja.
#
# Salida: 0 todo bien, 1 alguna falló, 2 detenido (límite o disco), 3 no empezó.
#
# Lista tomada de dockerlabs.es el 2026-11-06: 214 máquinas, 54.72 GiB.
# Las máquinas publicadas después de esa fecha no están incluidas.

set -u

DEST=./maquinas
PAUSA=3
SOLO=
SOLO_LISTAR=0
FORZAR=0
MARGEN=$((1024 * 1024 * 1024))

lista() {
  cat <<'LISTA'
1	Psycho	156677272	https://gestion-maquinas.dockerlabs.es/dl/psycho.zip
2	Dance-Samba	142955723	https://gestion-maquinas.dockerlabs.es/dl/dance-samba.zip
3	Pequeñas-Mentirosas	488960066	https://gestion-maquinas.dockerlabs.es/dl/pequenas-mentirosas.zip
4	Veneno	126761620	https://gestion-maquinas.dockerlabs.es/dl/veneno.zip
5	Injection	194503584	https://gestion-maquinas.dockerlabs.es/dl/injection.zip
6	Grandma	1212621603	https://gestion-maquinas.dockerlabs.es/dl/grandma.zip
7	Apolos	204397030	https://gestion-maquinas.dockerlabs.es/dl/apolos.zip
8	Report	281602912	https://gestion-maquinas.dockerlabs.es/dl/report.zip
9	Swiss	294263488	https://gestion-maquinas.dockerlabs.es/dl/swiss.zip
10	WhereIsMyWebShell	111185028	https://gestion-maquinas.dockerlabs.es/dl/whereismywebshell.zip
11	Inclusion	130303233	https://gestion-maquinas.dockerlabs.es/dl/inclusion.zip
12	Collections	491434922	https://gestion-maquinas.dockerlabs.es/dl/collections.zip
13	Trust	98542837	https://gestion-maquinas.dockerlabs.es/dl/trust.zip
14	Crackoff	596248696	https://gestion-maquinas.dockerlabs.es/dl/crackoff.zip
15	Predictable	187758064	https://gestion-maquinas.dockerlabs.es/dl/predictable.zip
16	BreakMySSH	48335933	https://gestion-maquinas.dockerlabs.es/dl/breakmyssh.zip
17	NodeClimb	161585435	https://gestion-maquinas.dockerlabs.es/dl/nodeclimb.zip
18	Library	236420264	https://gestion-maquinas.dockerlabs.es/dl/library.zip
19	ConsoleLog	397376953	https://gestion-maquinas.dockerlabs.es/dl/consolelog.zip
20	HackZones	132760946	https://gestion-maquinas.dockerlabs.es/dl/hackzones.zip
21	PingPong	241948937	https://gestion-maquinas.dockerlabs.es/dl/pingpong.zip
22	FirstHacking	110060777	https://gestion-maquinas.dockerlabs.es/dl/firsthacking.zip
23	Reverse	453288971	https://gestion-maquinas.dockerlabs.es/dl/reverse.zip
24	MyBB	187087350	https://gestion-maquinas.dockerlabs.es/dl/mybb.zip
25	Hidden	107652729	https://gestion-maquinas.dockerlabs.es/dl/hidden.zip
26	404-not-found	127543171	https://gestion-maquinas.dockerlabs.es/dl/404-not-found.zip
27	0xc0ffee	220517897	https://gestion-maquinas.dockerlabs.es/dl/0xc0ffee.zip
28	DebugMe	233994648	https://gestion-maquinas.dockerlabs.es/dl/debugme.zip
29	Stranger	179366258	https://gestion-maquinas.dockerlabs.es/dl/stranger.zip
30	Stack	285353504	https://gestion-maquinas.dockerlabs.es/dl/stack.zip
31	UserSearch	342053195	https://gestion-maquinas.dockerlabs.es/dl/usersearch.zip
32	Vulnerame	307797523	https://gestion-maquinas.dockerlabs.es/dl/vulnerame.zip
33	chmod-4755	153517125	https://gestion-maquinas.dockerlabs.es/dl/chmod-4755.zip
34	Lfi.elf	195285106	https://gestion-maquinas.dockerlabs.es/dl/lfi.elf.zip
35	Candy	354276531	https://gestion-maquinas.dockerlabs.es/dl/candy.zip
36	Verdejo	386288033	https://gestion-maquinas.dockerlabs.es/dl/verdejo.zip
37	HedgeHog	123608258	https://gestion-maquinas.dockerlabs.es/dl/hedgehog.zip
38	BorazuwarahCTF	121257346	https://gestion-maquinas.dockerlabs.es/dl/borazuwarahctf.zip
39	Sender	167983728	https://gestion-maquinas.dockerlabs.es/dl/sender.zip
40	Insecure	150798234	https://gestion-maquinas.dockerlabs.es/dl/insecure.zip
41	Upload	106822757	https://gestion-maquinas.dockerlabs.es/dl/upload.zip
42	Domain	151396275	https://gestion-maquinas.dockerlabs.es/dl/domain.zip
43	DevTools	125304832	https://gestion-maquinas.dockerlabs.es/dl/DevTools.zip
44	Move	323866083	https://gestion-maquinas.dockerlabs.es/dl/move.zip
45	Database	445825960	https://gestion-maquinas.dockerlabs.es/dl/database.zip
46	Vacaciones	165235201	https://gestion-maquinas.dockerlabs.es/dl/vacaciones.zip
47	Dark	270821720	https://gestion-maquinas.dockerlabs.es/dl/dark.zip
48	Rubiks	148581584	https://gestion-maquinas.dockerlabs.es/dl/Rubiks.zip
49	Forgotten_Portal	132344858	https://gestion-maquinas.dockerlabs.es/dl/forgotten_portal.zip
50	Force	374744520	https://gestion-maquinas.dockerlabs.es/dl/force.zip
51	SecretJenkins	342209342	https://gestion-maquinas.dockerlabs.es/dl/secretjenkins.zip
52	HiddenCat	290353911	https://gestion-maquinas.dockerlabs.es/dl/hiddencat.zip
53	Fileception	118132350	https://gestion-maquinas.dockerlabs.es/dl/fileception.zip
54	HackMeDaddy	133765656	https://gestion-maquinas.dockerlabs.es/dl/HackMeDaddy.zip
55	Backend	180463458	https://gestion-maquinas.dockerlabs.es/dl/backend.zip
56	Vulnvault	125578615	https://gestion-maquinas.dockerlabs.es/dl/vulnvault.zip
57	Allien	194172671	https://gestion-maquinas.dockerlabs.es/dl/allien.zip
58	HereBash	130013366	https://gestion-maquinas.dockerlabs.es/dl/herebash.zip
59	Subversion	139778778	https://gestion-maquinas.dockerlabs.es/dl/subversion.zip
60	Reflection	130189198	https://gestion-maquinas.dockerlabs.es/dl/reflection.zip
61	BadPlugin	324963607	https://gestion-maquinas.dockerlabs.es/dl/badplugin.zip
62	Raas	194485881	https://gestion-maquinas.dockerlabs.es/dl/raas.zip
63	Extraviado	126239677	https://gestion-maquinas.dockerlabs.es/dl/extraviado.zip
64	cineHack	126260929	https://gestion-maquinas.dockerlabs.es/dl/cinehack.zip
65	Seeker	320575041	https://gestion-maquinas.dockerlabs.es/dl/seeker.zip
66	Tproot	216910122	https://gestion-maquinas.dockerlabs.es/dl/tproot.zip
67	Internship	186463682	https://gestion-maquinas.dockerlabs.es/dl/internship.zip
68	Canario	284986911	https://gestion-maquinas.dockerlabs.es/dl/canario.zip
69	ApiBase	87407750	https://gestion-maquinas.dockerlabs.es/dl/apibase.zip
70	Gitea	408479176	https://gestion-maquinas.dockerlabs.es/dl/gitea.zip
71	secureLAB	313960951	https://gestion-maquinas.dockerlabs.es/dl/secureLAB.zip
72	StackInferno	337033579	https://gestion-maquinas.dockerlabs.es/dl/stackinferno.zip
73	ChocoPing	121113537	https://gestion-maquinas.dockerlabs.es/dl/chocoping.zip
74	Bicho	365812307	https://gestion-maquinas.dockerlabs.es/dl/bicho.zip
75	BaluFood	161319540	https://gestion-maquinas.dockerlabs.es/dl/balufood.zip
76	LogisticCloud	524322991	https://gestion-maquinas.dockerlabs.es/dl/logisticcloud.zip
77	galeria	238731012	https://gestion-maquinas.dockerlabs.es/dl/galeria.zip
78	Bypassme	142432915	https://gestion-maquinas.dockerlabs.es/dl/bypassme.zip
79	ApacheByte	217488682	https://gestion-maquinas.dockerlabs.es/dl/ApacheByte.zip
80	Minecraft	1062398706	https://gestion-maquinas.dockerlabs.es/dl/minecraft.zip
81	Status	271819023	https://gestion-maquinas.dockerlabs.es/dl/status.zip
82	Ejotapete	180734599	https://gestion-maquinas.dockerlabs.es/dl/ejotapete.zip
83	Grooti	258935599	https://gestion-maquinas.dockerlabs.es/dl/grooti.zip
84	Waffy	478244999	https://gestion-maquinas.dockerlabs.es/dl/waffy.zip
85	Aidor	119029505	https://gestion-maquinas.dockerlabs.es/dl/aidor.zip
86	Memesploit	268857971	https://gestion-maquinas.dockerlabs.es/dl/memesploit.zip
87	WalkingCMS	292186708	https://gestion-maquinas.dockerlabs.es/dl/walkingcms.zip
88	Mirame	196712558	https://gestion-maquinas.dockerlabs.es/dl/mirame.zip
89	Rutas	132917823	https://gestion-maquinas.dockerlabs.es/dl/rutas.zip
90	NorC	318519366	https://gestion-maquinas.dockerlabs.es/dl/norc.zip
91	ChatMe	251119778	https://gestion-maquinas.dockerlabs.es/dl/chatme.zip
92	ShowTime	249634737	https://gestion-maquinas.dockerlabs.es/dl/showtime.zip
93	Pinguinazo	491482837	https://gestion-maquinas.dockerlabs.es/dl/pinguinazo.zip
94	Balulero	253087305	https://gestion-maquinas.dockerlabs.es/dl/balulero.zip
95	Inj3ct0rss	334590797	https://gestion-maquinas.dockerlabs.es/dl/Inj3ct0rss.zip
96	ChocolateLovers	148304264	https://gestion-maquinas.dockerlabs.es/dl/chocolatelovers.zip
97	Sites	148242738	https://gestion-maquinas.dockerlabs.es/dl/sites.zip
98	Redirection	130157252	https://gestion-maquinas.dockerlabs.es/dl/redirection.zip
99	r00tless	342100322	https://gestion-maquinas.dockerlabs.es/dl/r00tless.zip
100	-Pn	320578891	https://gestion-maquinas.dockerlabs.es/dl/Pn.zip
101	BruteShock	242279246	https://gestion-maquinas.dockerlabs.es/dl/bruteshock.zip
102	Escolares	250832697	https://gestion-maquinas.dockerlabs.es/dl/escolares.zip
103	AnonymousPingu	242417797	https://gestion-maquinas.dockerlabs.es/dl/anonymouspingu.zip
104	File	145234047	https://gestion-maquinas.dockerlabs.es/dl/file.zip
105	HackPenguin	122297198	https://gestion-maquinas.dockerlabs.es/dl/hackpenguin.zip
106	FindYourStyle	163953363	https://gestion-maquinas.dockerlabs.es/dl/findyourstyle.zip
107	Buffered	286600065	https://gestion-maquinas.dockerlabs.es/dl/buffered.zip
108	Whoiam	195550113	https://gestion-maquinas.dockerlabs.es/dl/whoiam.zip
109	JenkHack	1125424374	https://gestion-maquinas.dockerlabs.es/dl/jenkhack.zip
110	Amor	186815581	https://gestion-maquinas.dockerlabs.es/dl/amor.zip
111	Darkweb	176334966	https://gestion-maquinas.dockerlabs.es/dl/darkweb.zip
112	Asucar	231048791	https://gestion-maquinas.dockerlabs.es/dl/asucar.zip
113	Road to Olympus	692746412	https://gestion-maquinas.dockerlabs.es/dl/Road_To_Olympus.zip
114	AguaDeMayo	478141990	https://gestion-maquinas.dockerlabs.es/dl/aduademayo.zip
115	Master	272699819	https://gestion-maquinas.dockerlabs.es/dl/master.zip
116	SkullNet	302148678	https://gestion-maquinas.dockerlabs.es/dl/skullnet.zip
117	Pressenter	233878278	https://gestion-maquinas.dockerlabs.es/dl/pressenter.zip
118	Los 40 Ladrones	129126501	https://gestion-maquinas.dockerlabs.es/dl/los40ladrones.zip
119	Picadilly	161583734	https://gestion-maquinas.dockerlabs.es/dl/picadilly.zip
120	Devil	338579543	https://gestion-maquinas.dockerlabs.es/dl/devil.zip
121	Winterfell	202100660	https://gestion-maquinas.dockerlabs.es/dl/winterfell.zip
122	Mapache2	129900643	https://gestion-maquinas.dockerlabs.es/dl/mapache2.zip
123	StrongJenkins	712966500	https://gestion-maquinas.dockerlabs.es/dl/strongjenkins.zip
124	HackTheHeaven	150449840	https://gestion-maquinas.dockerlabs.es/dl/hacktheheaven.zip
125	Pntopntobarra	128822049	https://gestion-maquinas.dockerlabs.es/dl/pntopntobarra.zip
126	PyRed	105350015	https://gestion-maquinas.dockerlabs.es/dl/pyred.zip
127	Flow	133473335	https://gestion-maquinas.dockerlabs.es/dl/flow.zip
128	LittlePivoting	428142789	https://gestion-maquinas.dockerlabs.es/dl/LittlePivoting.zip
129	DockHackLab	241655312	https://gestion-maquinas.dockerlabs.es/dl/dockhacklab.zip
130	Paradise	235293152	https://gestion-maquinas.dockerlabs.es/dl/paradise.zip
131	SummerVibes	232514419	https://gestion-maquinas.dockerlabs.es/dl/summervibes.zip
132	Bashpariencias	125085098	https://gestion-maquinas.dockerlabs.es/dl/bashpariencias.zip
133	BigPivoting	880743897	https://gestion-maquinas.dockerlabs.es/dl/BigPivoting.zip
135	Fooding	496033734	https://gestion-maquinas.dockerlabs.es/dl/fooding.zip
136	Stellarjwt	152144869	https://gestion-maquinas.dockerlabs.es/dl/stellarjwt.zip
137	Queuemedic	227968456	https://gestion-maquinas.dockerlabs.es/dl/Queuemedic.zip
138	ChocolateFire	309210352	https://gestion-maquinas.dockerlabs.es/dl/chocolatefire.zip
139	DoubleTrouble	257874285	https://gestion-maquinas.dockerlabs.es/dl/doubletrouble.zip
140	Eclipse	568065156	https://gestion-maquinas.dockerlabs.es/dl/eclipse.zip
141	DockerLabs	99156964	https://gestion-maquinas.dockerlabs.es/dl/dockerlabs.zip
142	Wallet	216445332	https://gestion-maquinas.dockerlabs.es/dl/wallet.zip
143	Cachopo	244710559	https://gestion-maquinas.dockerlabs.es/dl/cachopo.zip
144	Obsession	146554522	https://gestion-maquinas.dockerlabs.es/dl/obsession.zip
145	DoubleFlow	363478541	https://gestion-maquinas.dockerlabs.es/dl/doubleflow.zip
146	Elevator	364643847	https://gestion-maquinas.dockerlabs.es/dl/elevator.zip
147	Cracker	127192185	https://gestion-maquinas.dockerlabs.es/dl/cracker.zip
148	Spain	845450240	https://gestion-maquinas.dockerlabs.es/dl/spain.tar
149	Express	245492635	https://gestion-maquinas.dockerlabs.es/dl/express.zip
150	Patriaquerida	136129926	https://gestion-maquinas.dockerlabs.es/dl/patriaquerida.zip
151	Insanity	331596961	https://gestion-maquinas.dockerlabs.es/dl/insanity.zip
152	Lifeordead	136362206	https://gestion-maquinas.dockerlabs.es/dl/lifeordead.zip
153	Unrecover	196493688	https://gestion-maquinas.dockerlabs.es/dl/unrecover.zip
154	Walking Dead	139060150	https://gestion-maquinas.dockerlabs.es/dl/walking_dead.zip
155	ApiRoot	152170504	https://gestion-maquinas.dockerlabs.es/dl/apiroot.zip
156	Smashing	352991183	https://gestion-maquinas.dockerlabs.es/dl/smashing.zip
157	MachuPicchu	1341361860	https://gestion-maquinas.dockerlabs.es/dl/machupichhu.zip
158	Crystalteam	207472286	https://gestion-maquinas.dockerlabs.es/dl/crystalteam.zip
159	Gallery	338084515	https://gestion-maquinas.dockerlabs.es/dl/Gallery.zip
160	Ciberguard	245011946	https://gestion-maquinas.dockerlabs.es/dl/ciberguard.zip
161	TheDog	294571082	https://gestion-maquinas.dockerlabs.es/dl/thedog.zip
162	PkgPoison	171647501	https://gestion-maquinas.dockerlabs.es/dl/pkgpoison.zip
163	Ofuskeit	402991487	https://gestion-maquinas.dockerlabs.es/dl/ofuskeit.zip
164	ForbiddenHack	184512179	https://gestion-maquinas.dockerlabs.es/dl/forbiddenhack.zip
165	Bola	184524175	https://gestion-maquinas.dockerlabs.es/dl/bola.zip
166	InfluencerHate	127097820	https://gestion-maquinas.dockerlabs.es/dl/influencerhate.zip
167	WinFake	133370196	https://gestion-maquinas.dockerlabs.es/dl/winfake.zip
168	PingCTF	215327563	https://gestion-maquinas.dockerlabs.es/dl/ping_ctf.zip
169	SpiderRoot	145709179	https://gestion-maquinas.dockerlabs.es/dl/SpiderRoot.zip
172	Crossfi	236006297	https://gestion-maquinas.dockerlabs.es/dl/crossfi.zip
174	Ekisese	450178335	https://gestion-maquinas.dockerlabs.es/dl/ekisese.zip
175	Perrito Mágico	282684712	https://gestion-maquinas.dockerlabs.es/dl/perrito_magico.zip
183	Race	233349095	https://gestion-maquinas.dockerlabs.es/dl/race.zip
184	SocialHub	392961668	https://gestion-maquinas.dockerlabs.es/dl/socialhub.zip
185	Jason	281179062	https://gestion-maquinas.dockerlabs.es/dl/jason.zip
186	Tokenaso	142190826	https://gestion-maquinas.dockerlabs.es/dl/tokenaso.zip
187	Puzzle	213687544	https://gestion-maquinas.dockerlabs.es/dl/puzzle.zip
188	Wargames	228847473	https://gestion-maquinas.dockerlabs.es/dl/wargames.zip
189	Rolarola	37393030	https://gestion-maquinas.dockerlabs.es/dl/rolarola.zip
209	Profetas	220140059	https://gestion-maquinas.dockerlabs.es/dl/profetas.zip
217	RootedPingu	243793920	https://gestion-maquinas.dockerlabs.es/dl/rootedpingu.zip
218	Internal	224287686	https://gestion-maquinas.dockerlabs.es/dl/internal.zip
219	Talent	335900684	https://gestion-maquinas.dockerlabs.es/dl/talent.zip
220	CuentaAtrás	304306391	https://gestion-maquinas.dockerlabs.es/dl/cuentaatras.zip
222	Flasky	83287710	https://gestion-maquinas.dockerlabs.es/dl/flasky.zip
225	BigWear	559780212	https://gestion-maquinas.dockerlabs.es/dl/bigwear.zip
226	NightBlade	714127073	https://gestion-maquinas.dockerlabs.es/dl/nightblade.zip
234	SECorNOTsec	174794734	https://gestion-maquinas.dockerlabs.es/dl/secornotsec.zip
238	Autoescuela	458717458	https://gestion-maquinas.dockerlabs.es/dl/autoescuela.zip
242	WorkConnect	83984283	https://gestion-maquinas.dockerlabs.es/dl/workconnect.zip
243	Duque	143718167	https://gestion-maquinas.dockerlabs.es/dl/duque.zip
245	TrailPack	65158018	https://gestion-maquinas.dockerlabs.es/dl/trailpack.zip
249	Adopting	378151435	https://gestion-maquinas.dockerlabs.es/dl/adopting.zip
254	Gotham	107479040	https://gestion-maquinas.dockerlabs.es/dl/gotham.zip
255	PinguPenguin	203775095	https://gestion-maquinas.dockerlabs.es/dl/pingupenguin.zip
264	ApkAdmin	52533712	https://gestion-maquinas.dockerlabs.es/dl/apkadmin.zip
268	kmspwned	116916224	https://gestion-maquinas.dockerlabs.es/dl/kmspwned.zip
271	BaluHome	407679552	https://gestion-maquinas.dockerlabs.es/dl/baluhome.zip
281	PipePwned	206937959	https://gestion-maquinas.dockerlabs.es/dl/pipepwned.zip
282	hannah_coffee	128254411	https://gestion-maquinas.dockerlabs.es/dl/hannah_coffee.zip
283	Los 3 Hackers	107740927	https://gestion-maquinas.dockerlabs.es/dl/los3hackers.zip
292	Acme	200291848	https://gestion-maquinas.dockerlabs.es/dl/acme.zip
293	Zabbixploit	111740220	https://gestion-maquinas.dockerlabs.es/dl/zabbixploit.zip
295	Baremetal	58229736	https://gestion-maquinas.dockerlabs.es/dl/Baremetal.zip
296	Asturias	167003226	https://gestion-maquinas.dockerlabs.es/dl/asturias.zip
297	Flynn	85384269	https://gestion-maquinas.dockerlabs.es/dl/flynn.zip
298	Analyst	61788080	https://gestion-maquinas.dockerlabs.es/dl/analyst.zip
299	Bigbank	88473824	https://gestion-maquinas.dockerlabs.es/dl/bigbank.zip
300	Decompile	340391628	https://gestion-maquinas.dockerlabs.es/dl/decompile.zip
304	DeepLab	174938579	https://gestion-maquinas.dockerlabs.es/dl/deeplab.zip
305	Novatech	104396114	https://gestion-maquinas.dockerlabs.es/dl/novatech.zip
306	Vaultix-v6	87760034	https://gestion-maquinas.dockerlabs.es/dl/vaultix-v6.zip
307	Tron	190037196	https://gestion-maquinas.dockerlabs.es/dl/tron.zip
309	MicroBug	4270454593	https://gestion-maquinas.dockerlabs.es/dl/MicroBug.zip
342	TocTou	89774191	https://gestion-maquinas.dockerlabs.es/dl/toctou.zip
LISTA
}

ayuda() { sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; }

bytes_de() { if [ -f "$1" ]; then echo $(($(wc -c <"$1"))); else echo 0; fi; }

humano() { awk -v b="$1" 'BEGIN { if (b >= 1073741824) printf "%.2f GiB", b / 1073741824; else printf "%.1f MiB", b / 1048576 }'; }

minusculas() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Lista aplicando --solo.
filtrada() {
  local id nombre tam url archivo
  while IFS=$'\t' read -r id nombre tam url; do
    archivo=${url##*/}
    case ",$SOLO," in
      ,,|*,"$(minusculas "${archivo%.*}")",*) printf '%s\t%s\t%s\t%s\n' "$id" "$nombre" "$tam" "$url" ;;
    esac
  done < <(lista)
}

while [ $# -gt 0 ]; do
  case "$1" in
    --lista) SOLO_LISTAR=1 ;;
    --forzar) FORZAR=1 ;;
    --solo)
      [ $# -ge 2 ] || { echo "Falta el valor de --solo" >&2; exit 3; }
      SOLO=$(minusculas "$2"); shift ;;
    --pausa)
      [ $# -ge 2 ] || { echo "Falta el valor de --pausa" >&2; exit 3; }
      case "$2" in ''|*[!0-9]*) echo "--pausa necesita un número de segundos" >&2; exit 3 ;; esac
      PAUSA=$2; shift ;;
    -h|--help) ayuda; exit 0 ;;
    -*) echo "Opción desconocida: $1" >&2; ayuda >&2; exit 3 ;;
    *) DEST=$1 ;;
  esac
  shift
done

if [ -n "$SOLO" ]; then
  for pedido in ${SOLO//,/ }; do
    if ! lista | cut -f4 | grep -qiF "/$pedido."; then
      echo "No existe ninguna máquina llamada '$pedido' (mira --lista)" >&2
      exit 3
    fi
  done
fi

TOTAL=0
BYTES=0
while IFS=$'\t' read -r _id _nombre _tam _url; do
  TOTAL=$((TOTAL + 1))
  BYTES=$((BYTES + _tam))
done < <(filtrada)

if [ "$SOLO_LISTAR" = 1 ]; then
  while IFS=$'\t' read -r _id _nombre _tam _url; do
    _archivo=${_url##*/}
    printf '%-28s %-28s %12s\n' "${_archivo%.*}" "$_nombre" "$(humano "$_tam")"
  done < <(filtrada)
  echo
  echo "Máquinas: $TOTAL  |  Total: $(humano "$BYTES")"
  exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "Hace falta curl." >&2; exit 3; }

HAY_UNZIP=1
if ! command -v unzip >/dev/null 2>&1; then
  HAY_UNZIP=0
  echo "AVISO: no hay unzip; los .zip solo se comprobarán por tamaño." >&2
fi

mkdir -p "$DEST" || { echo "No se puede crear $DEST" >&2; exit 3; }

# Espacio: lo que falta por bajar frente a lo libre en el destino.
FALTA=0
while IFS=$'\t' read -r _id _nombre _tam _url; do
  _archivo=${_url##*/}
  _hay=$(bytes_de "$DEST/$_archivo")
  [ "$_hay" -gt 0 ] || _hay=$(bytes_de "$DEST/$_archivo.part")
  [ "$_hay" -lt "$_tam" ] && FALTA=$((FALTA + _tam - _hay))
done < <(filtrada)

LIBRE=$(($(df -Pk "$DEST" | awk 'NR==2 { print $4 }') * 1024))
echo "Destino: $DEST"
echo "Máquinas: $TOTAL  |  Falta por bajar: $(humano "$FALTA")  |  Libre: $(humano "$LIBRE")"

if [ $((FALTA + MARGEN)) -gt "$LIBRE" ] && [ "$FORZAR" = 0 ]; then
  echo >&2
  echo "No hay espacio suficiente (se deja 1 GiB de margen). No se ha descargado nada." >&2
  echo "Usa otra carpeta, elige algunas con --solo, o empieza igual con --forzar." >&2
  exit 3
fi

BAJADAS=0
YA_ESTABAN=0
FALLIDAS=()
SEGUIDAS=0

resumen() {
  local f
  echo
  echo "Bajadas ahora: $BAJADAS  |  Ya estaban: $YA_ESTABAN  |  Fallidas: ${#FALLIDAS[@]}"
  if [ "${#FALLIDAS[@]}" -gt 0 ]; then
    : >"$DEST/fallidas.txt"
    for f in "${FALLIDAS[@]}"; do
      echo "  - $f"
      echo "$f" >>"$DEST/fallidas.txt"
    done
    echo "Lista guardada en $DEST/fallidas.txt. Relanza el script para reintentarlas."
  else
    rm -f "$DEST/fallidas.txt"
  fi
}

detener() {
  echo >&2
  echo "$1" >&2
  echo "Lo ya bajado se conserva: relanza el script para continuar." >&2
  resumen
  exit 2
}

parar_por_limite() {
  detener "El servidor responde HTTP $1 (límite o bloqueo). Me detengo: mejor reintentar más tarde."
}

trap 'detener "Interrumpido."' INT TERM

fallo() {
  echo "  FALLO: $2" >&2
  FALLIDAS+=("$1: $2")
  SEGUIDAS=$((SEGUIDAS + 1))
  if [ "$SEGUIDAS" -ge 5 ]; then
    detener "5 fallos seguidos: revisa la conexión o el estado del sitio."
  fi
}

# Deja en HTTP_CODE y REMOTO la respuesta actual del servidor.
consultar() {
  local linea
  linea=$(curl -sSIL --connect-timeout 30 --max-time 60 "$1" 2>/dev/null | tr -d '\r' | awk '
    toupper($1) ~ /^HTTP\// { c = $2; l = "" }
    tolower($1) == "content-length:" { l = $2 }
    END { print c, l }')
  HTTP_CODE=${linea%% *}
  REMOTO=${linea#* }
  case "$HTTP_CODE" in ''|*[!0-9]*) HTTP_CODE=0 ;; esac
  case "$REMOTO" in ''|*[!0-9]*) REMOTO=0 ;; esac
}

if [ -t 2 ]; then PROGRESO=(-#); else PROGRESO=(-sS); fi

# Baja $1 a $2 hasta tener $3 bytes, continuando donde se quedó.
bajar() {
  local intento codigo rc
  for intento in 1 2 3; do
    [ "$(bytes_de "$2")" -eq "$3" ] && return 0
    codigo=$(curl -f -L -C - "${PROGRESO[@]}" --connect-timeout 30 \
      --speed-limit 1024 --speed-time 120 -o "$2" -w '%{http_code}' "$1")
    rc=$?
    case "$codigo" in 403|429|503) parar_por_limite "$codigo" ;; esac
    [ "$rc" -eq 23 ] && detener "No se puede escribir en $DEST (¿disco lleno?)."
    [ "$rc" -eq 0 ] && return 0
    echo "  Corte (curl $rc, HTTP $codigo), intento $intento de 3." >&2
    [ "$intento" -lt 3 ] && sleep 15
  done
  return 1
}

# $1 ruta del archivo, $2 nombre real (para saber el tipo).
verificar() {
  case "$2" in
    *.zip)
      [ "$HAY_UNZIP" = 1 ] || return 0
      unzip -tqq "$1" </dev/null >/dev/null 2>&1
      # 1 = avisos sin daño; 5, 81 y 82 = cifrado, no se puede comprobar sin clave.
      case $? in 0|1|5|81|82) return 0 ;; *) return 1 ;; esac ;;
    *.tar) tar -tf "$1" >/dev/null 2>&1 ;;
    *) return 0 ;;
  esac
}

n=0
pausar=0
while IFS=$'\t' read -r id nombre tam url <&3; do
  n=$((n + 1))
  archivo=${url##*/}
  final=$DEST/$archivo
  parte=$final.part

  consultar "$url"
  case "$HTTP_CODE" in
    200) ;;
    403|429|503) parar_por_limite "$HTTP_CODE" ;;
    *) echo "[$n/$TOTAL] $nombre"; fallo "$nombre" "el servidor responde HTTP $HTTP_CODE"; continue ;;
  esac
  [ "$REMOTO" -gt 0 ] || REMOTO=$tam

  if [ -f "$final" ] && [ "$(bytes_de "$final")" -eq "$REMOTO" ]; then
    YA_ESTABAN=$((YA_ESTABAN + 1))
    continue
  fi

  [ "$pausar" = 1 ] && sleep "$PAUSA"
  pausar=1
  echo "[$n/$TOTAL] $nombre ($(humano "$REMOTO"))"

  [ "$(bytes_de "$parte")" -gt "$REMOTO" ] && rm -f "$parte"

  if ! bajar "$url" "$parte" "$REMOTO"; then
    fallo "$nombre" "no se pudo completar la descarga"
    continue
  fi
  if [ "$(bytes_de "$parte")" -ne "$REMOTO" ]; then
    fallo "$nombre" "tamaño incorrecto: $(bytes_de "$parte") de $REMOTO bytes"
    continue
  fi
  if ! verificar "$parte" "$archivo"; then
    mv -f "$parte" "$final.invalido"
    fallo "$nombre" "archivo dañado, guardado como $archivo.invalido"
    continue
  fi

  mv -f "$parte" "$final"
  rm -f "$final.invalido"
  BAJADAS=$((BAJADAS + 1))
  SEGUIDAS=0
done 3< <(filtrada)

resumen
[ "${#FALLIDAS[@]}" -eq 0 ]
