# Registro de cambios

## 4.1.0 — Diseños de botones
### Nuevo
- **Diseños de los controles táctiles** (Ajustes > Controles táctiles > Diseño de los botones): Clásico (el de siempre, por defecto), Consola (botones de colores con relieve, según el mando de cada sistema), Minimalista, Neón, Pixel y Cristal. Valen para todas las consolas y también se ven en el editor de controles. Cada uno se muestra con una vista previa.

### Correcciones
- **iPhone: los juegos dejaban de abrirse tras actualizar la app (PSP cerraba la app).** iOS cambia el nombre de la carpeta de la app (`.../Application/<UUID>/`) con cada instalación, y la biblioteca guardaba la ruta completa de cada juego, portada y save state. Ahora, al abrirse, la app corrige las rutas que apuntan a una instalación anterior. Además, el motor comprueba que el juego exista antes de dárselo a los núcleos que lo leen por su cuenta: PPSSPP arrancaba sin juego y se cerraba (diagnosticado con los informes de cierre del iPhone).
- **iPhone:** el hilo de emulación se crea con 16 MB de pila (iOS da 512 KB a los hilos secundarios) y, si un núcleo con GPU no obtiene su contexto, ya no se ejecuta.
- **iPhone: registro de diagnóstico** en Archivos > RetroStation > Registro (`registro.txt` y `registro-anterior.txt`, el de la sesión anterior).
- **Ajustes > Fondo:** «Negro AMOLED» no cambiaba nada porque el fondo animado de circuitos siempre se pintaba en gris carbón. Ahora usa negro puro con pistas más tenues.

## 4.0.0 — RetroStation para iPhone y Sega Mega Drive
Versión mayor: nueva plataforma (iOS) y nueva consola.

### iPhone (iOS 15 o posterior)
- **Compilación en la nube** con un Mac de GitHub Actions (`.github/workflows/ios.yml`). Genera el `.ipa` sin firmar; se instala con iloader o SideStore usando el Apple ID del usuario.
- **Motor:**
  - sonido con CoreAudio (RemoteIO);
  - imagen como textura de Flutter (CVPixelBuffer BGRA en `AppDelegate.swift`);
  - PSP con OpenGL ES (EAGL, `native/frontend/hw_render_ios.mm`).
- **Emuladores:** NES, SNES, Game Boy/GBC/GBA, cable link de GBA, PlayStation, Nintendo DS, link de Pokémon (gpSP), Mega Drive y PSP. iOS no permite JIT, así que PS1, DS, gpSP y PSP usan sus intérpretes (PSP con el intérprete IR de PPSSPP).
- Cada emulador se compila por separado; la app detecta al abrirse cuáles lleva dentro y marca el resto como «próximamente».
- **Mandos:** Pro Controller, Xbox, PlayStation y MFi con GameController, con el mismo sistema que el PC (menús, Home para el menú del juego, Ajustes > Mando).
- **Juegos:** se pueden pasar con la app Archivos o con «Enviar juegos» desde otro dispositivo.
- **Limitación:** la búsqueda automática de jugadores en la red necesita un permiso especial de Apple; en iPhone se puede usar «Conectar por IP».

### Sega Mega Drive / Genesis (todas las plataformas)
- Emulador Genesis Plus GX (`native/cores/genesis_plus_gx.cmake`).
- Formatos `.md`, `.gen` y `.smd`; al importar se comprueba la cabecera «SEGA».
- Controles táctiles A, B y C en diagonal, como el mando original.
- Juego compartido por la red.
- Probado en el PC con Cave Story MD (homebrew gratuito): 60 FPS.

### Repositorio y descargas
- Código en GitHub: https://github.com/JoseLuisCruz29/RetroStation
- Cada versión se publica en *Releases* con el instalador de Windows, el APK y el IPA, sin juegos comerciales.

## 3.7.0 — Multijugador de PSP (ad hoc)
- **Ad hoc de PSP** en la sala: los juegos de PSP que tienen los dos (el mismo archivo) aparecen como «Ad hoc de PSP · cada uno con su PSP y su partida». Es el multijugador inalámbrico de la propia PSP, que emula PPSSPP. No usa el motor de netplay: cada dispositivo ejecuta su juego, con su mando y su partida.
  - El anfitrión enciende la Wi-Fi de la PSP y el servidor PRO Ad Hoc de PPSSPP (puertos TCP 27312 y 27313), y se conecta a sí mismo (`localhost`).
  - El invitado se conecta a la IP del anfitrión, que PPSSPP pide cifra a cifra en 12 opciones (`pspAdhocOptions` en `lib/multiplayer/multiplayer_games.dart`).
  - Cada PSP usa una MAC al azar, y el apodo de la PSP es el nombre del multijugador (`rs_username`, que el motor entrega por `RETRO_ENVIRONMENT_GET_USERNAME`).
- Los estados de guardado siguen disponibles en ad hoc (cada uno juega su partida). En el juego, una etiqueta indica con quién estás conectado.
- **Corrección (Windows):** el motor inicializa Winsock antes de cargar el núcleo. Sin eso, el servidor ad hoc de PPSSPP fallaba con el error 10093 (`WSANOTINITIALISED`). Probado: el servidor escucha y acepta conexiones.

## 3.6.0 — Mandos en el PC
- **Mandos en Windows** (`windows/runner/gamepad_input.cpp`): se leen con la API de joystick de Windows (winmm), que ve cualquier mando HID por USB o Bluetooth. Un hilo los lee cada 4 ms, cada 2 s busca mandos nuevos y envía los cambios a Dart por el canal `retrostation/gamepad`.
- **Pro Controller de Switch leído por HID** (`windows/runner/nintendo_hid.h`), como hacen SDL o Steam. Con Steam abierto, el mando pasa al modo completo de Nintendo (informe 0x30) y la API de Windows ya no recibe pulsaciones. RetroStation lee los dos modos, pide el modo completo y enciende la luz del jugador 1 (deja de parpadear). La entrada "fantasma" que Windows deja del mando emparejado se ignora.
- **Calidad gráfica en el PC** (Ajustes > Juego): Original, Alta (2×) o Máxima (3×). Sube la resolución interna de PSP (960×544 o 1440×816) y activa la resolución mejorada de PlayStation; lo elegido a mano en Consolas > PSP manda. Probado en este PC: PSP a 3× y PlayStation a 2×, ambos a 60 FPS. Por defecto, Alta.
- **Pro Controller de Switch** reconocido (057E:2009), con su distribución: A, B, X e Y en su sitio; L/ZL y R/ZR como L y R; + es Start, − es Select y Home abre o cierra el menú del juego. Los mandos de Xbox y los genéricos usan los botones por posición.
- La cruceta del mando siempre es la cruceta. El joystick izquierdo también la mueve, y en PSP funciona como joystick analógico.
- **Ajustes > Mando**: muestra los mandos conectados y lo que se pulsa en cada momento, y deja cambiar cada botón pulsándolo en el mando. Si el botón ya lo usaba otra acción, se intercambian. Hay botón Restablecer.
- Bajo el juego se indica el mando conectado y qué botón abre el menú.
- **Menús con el mando** (`lib/controllers/gamepad_navigator.dart`): la cruceta o el joystick mueven el cursor por la app (enfoque direccional de Flutter, con repetición al mantener), A o Start eligen y B vuelve o cierra diálogos. Las tarjetas de Inicio (`RetroPanel`) se pueden enfocar y se iluminan con el color de acento. Durante el juego el mando es solo del juego; con el menú del juego abierto, vuelve a mover el menú.
- **Pantalla completa con F11** en el PC (`windows/runner/main.cpp`, `FlutterWindow::ToggleFullscreen`): sin bordes en el monitor de la ventana; otra vez F11 recupera el tamaño y la posición.
- `native/tools/joy_probe.cpp` y `hid_probe.cpp`: listan los mandos que ve Windows y muestran las pulsaciones y los informes HID del Pro Controller.

## 3.5.0 — Enviar juegos, teclas en el PC e instalador
- **Enviar juegos a otro dispositivo** (`lib/multiplayer/game_transfer.dart`): desde Multijugador LAN, con el icono de envío de cada dispositivo encontrado, se eligen juegos de la biblioteca y se copian por la Wi-Fi (puerto TCP 55438). Funciona entre teléfonos y entre PC y teléfono.
  - El otro dispositivo ve quién envía, qué juegos y cuánto ocupan, y decide si recibir. Hay barra de progreso y botón Cancelar.
  - Los discos `.cue` viajan con sus pistas `.bin`.
  - Lo recibido se importa como cualquier ROM: se valida la cabecera, se descartan duplicados y se aceptan nombres con acentos.
  - Límites: 64 archivos y 8 GB por envío; los nombres de archivo se sanean.
- **Teclas configurables en el PC** (Ajustes > Teclado, `lib/controllers/keyboard_bindings.dart`): cada botón (cruceta, A, B, X, Y, L, R, Start y Select) se asigna a la tecla que se quiera. Si la tecla ya la usaba otro botón, se intercambian. La ayuda bajo el juego muestra las teclas elegidas y los mandos siguen funcionando siempre.
- **Instalador para compartir la versión de PC** (`tool/build_compartir.ps1`): compila la app sin los juegos comerciales (solo el homebrew de `bundled.json`) y genera `RetroStation-<versión>-Instalador.exe` con IExpress. El instalador tiene el logo como icono (`tool/installer/set_exe_icon.cpp`) y una ventana donde se elige la carpeta (por defecto `%LOCALAPPDATA%\Programs\RetroStation`, con botón Examinar) y si se quieren accesos directos en el Escritorio y en el menú Inicio. No pide permisos de administrador y añade la entrada para desinstalar en Configuración > Aplicaciones; al desinstalar se conservan los juegos y las partidas. También genera el APK para compartir.

## 3.4.0 — PSP en el PC
- **PSP en Windows** (PPSSPP con JIT x86-64). Se compila aparte con `tool/build_ppsspp_windows.ps1` (CMake oficial con `-DLIBRETRO=ON` y MSVC); `build_windows_native.ps1` lo copia como `libppsspp_libretro.dll`. Parche en PPSSPP: `draw_text_uwp.cpp` no se compila en libretro (su cabecera ya lo excluía).
- **OpenGL de escritorio en el motor** (`native/frontend/hw_render_win.cpp`): contexto WGL en una ventana oculta y FBO propio. Cada fotograma se lee y se entrega a Flutter por el mismo camino que el resto de consolas (`rs_copy_frame`). En portátiles con dos GPU pide la dedicada. Probado: Dragon Ball Z Tenkaichi Tag Team a 60 FPS.
- Ya no queda ninguna consola sin soporte en Windows.

### Correcciones
- **Juegos con acentos o eñes en el nombre** ("Pokémon Edición Negra 2"...) no se abrían en el PC ("No se pudo leer el ROM"). Las rutas llegan al motor en UTF-8 y los núcleos usan `fopen`, que en Windows esperaba la página de códigos del sistema. Ahora la app declara UTF-8 en su manifiesto (`activeCodePage`), lo que también arregla las partidas guardadas y los BIOS con esos nombres. En Android no pasaba.
- `core_smoke` pasa las rutas en UTF-8 como la app y puede guardar una captura (`RS_SHOT`).

## 3.3.0 — PS1 y DS en el PC
- **PlayStation en Windows** (PCSX ReARMed con intérprete). Como en su compilación oficial para Windows: `mmap` emulado (`deps/mman`) y sin audio asíncrono. La memoria de la PlayStation se reserva donde Windows la da (`native/compat/win/pcsx_win_map.c`); antes pedía direcciones fijas y en la app fallaba con "mapping main RAM failed". Probado: Marvel Super Heroes vs. Street Fighter a 60 FPS.
- **Nintendo DS en Windows** (melonDS, intérprete). Su JIT para x64 falla con el ABI de MSVC, pero un PC va de sobra sin él. Probado: Pokémon Edición Negra 2 a 60 FPS.
- Capa de compatibilidad POSIX para Windows (`native/compat/win`: `unistd.h`, `strings.h`, `sys/time.h`, `strcasecmp` y `localtime_r`).
- **Sonidos de los menús en el PC** (canal `retrostation/sfx` en `windows/runner/ui_sound.cpp`, con los mismos WAV que en Android). Antes, en Windows no sonaban.
- **Accesos directos**: RetroStation se instala en `%LOCALAPPDATA%\Programs\RetroStation`, con acceso en el Escritorio y en el menú Inicio.
- Herramienta `native/tools/core_smoke.cpp`: carga un núcleo con el motor, sin la interfaz, y muestra los FPS.
- En Windows solo falta **PSP**: PPSSPP necesita OpenGL por hardware.

## 3.2.0 — Cable link de GBA para cualquier juego
Función nueva: multijugador por cable link con cualquier juego de GBA (Kirby: Nightmare in Dream Land, Mario Kart Super Circuit...). Cada jugador usa su ROM (la misma), su dispositivo, sus controles y su partida guardada. Funciona entre teléfonos y entre el PC y un teléfono.

- **Núcleo "GBA Link"** (`native/gbalink/gbalink_core.cpp`, libretro, con mGBA 0.10.5 como biblioteca):
  - cada dispositivo emula las dos GBA unidas por el cable de mGBA (el mismo protocolo que su versión de PC), por turnos en un solo hilo y siempre en el mismo orden;
  - con las mismas pulsaciones, el resultado es idéntico: comprobado en el PC y en el Galaxy A13 (ARM de 32 bits);
  - por la Wi-Fi solo viajan los botones;
  - cada uno ve y oye su GBA, y la del otro no se dibuja (ahorra trabajo sin cambiar la emulación).
- **Partidas**: al pulsar Empezar, el anfitrión pide la partida guardada del invitado y envía la suya. Las dos GBA arrancan iguales en los dos dispositivos y, al terminar, cada uno guarda solo su progreso (el mismo `.srm` que al jugar solo con mGBA).
- **Red**: modo lockstep sin estado inicial (las dos consolas empiezan a la vez desde el encendido). La red se inicia antes del primer fotograma.
- **Sala**: aparecen todos los juegos de GBA que tenéis los dos (mismo archivo) como "Cable link de GBA". El link de Pokémon con gpSP sigue disponible, también con ediciones distintas.
- **Probado**: con Kirby: Nightmare in Dream Land, la pantalla de conexión reconoce P1 y P2 y la partida de Quick Draw a 2 jugadores funciona; entre el PC y el teléfono iba a 56-59 FPS con 14-16 ms.

### Mejoras de red
- **Margen automático**: antes de empezar se mide la latencia (5 pings) y se elige el retraso de entrada, entre 3 y 8 fotogramas, según la red.
- **Wi-Fi de baja latencia en Android** durante las partidas (WifiLock `LOW_LATENCY`): sin él, el ahorro de energía subía la latencia a unos 80 ms y el juego bajaba de 60 FPS.
- **Descubrimiento en los dos sentidos**: cada dispositivo responde directamente a quien se anuncia. Antes, un PC con varias redes (VPN, Ethernet) veía al teléfono, pero el teléfono no veía al PC.

### Windows
- La versión de Windows incluye el runtime de Visual C++ (`msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`), así que funciona en PCs que no lo tienen instalado.
- Textos de Novedades, tutorial, Inicio y Multijugador actualizados.

## 3.1.0 — RetroStation para Windows
Función nueva: la app funciona en el PC con Windows y el multijugador LAN conecta el PC con un teléfono.

- **App de Windows** (`flutter build windows`): misma interfaz, tutorial y biblioteca. Se juega con teclado (flechas, X/Z/C/V, A/S, Intro, Retroceso) o con mando, con una guía de teclas bajo la imagen. Ventana "RetroStation" con tu logo, y "Jose Cruz" como autor en el ejecutable.
- **Motor nativo para Windows**, compilado con el Clang de Visual Studio (`tool/build_windows_native.ps1`):
  - audio con **WASAPI**;
  - la imagen se envía a Flutter como textura de píxeles (`windows/runner/native_video.cpp`);
  - los núcleos se cargan como DLL;
  - la red del multijugador usa Winsock (`native/frontend/net_socket.h`), y el mismo código sirve para Android.
- **Consolas en Windows**: NES (FCEUmm), SNES (Snes9x), Game Boy, Game Boy Color y GBA (mGBA), y gpSP para el link de Pokémon. **PS1, DS y PSP todavía no** (sus núcleos usan piezas de Linux u OpenGL ES que hay que adaptar); la app lo explica en lugar de fallar.
- **Multijugador PC ↔ teléfono** probado en la misma Wi-Fi: el PC y el Galaxy A13 se encuentran solos, la petición de conexión y la sala funcionan, y salen los juegos que tienen los dos.
- La primera vez, Windows pregunta por el **Firewall**: hay que pulsar "Permitir". La sección Multijugador lo recuerda en el PC.

### Corregido
- La sala podía ofrecer un juego que el otro dispositivo no puede abrir: un PS1 al PC, que salía con "No se pudo abrir el núcleo". Ahora cada dispositivo solo comparte los juegos de consolas que puede emular, así que la sala solo muestra lo que funciona en los dos.

## 3.0.0 — Multijugador LAN
Versión mayor: multijugador entre dos teléfonos en la misma Wi-Fi (sin internet). Cada jugador juega en su propio teléfono con sus controles.

- **Perfil**: nombre de jugador que se elige una vez y se guarda en el teléfono.
- **Multijugador LAN** (Inicio > Multijugador): encuentra automáticamente los teléfonos con RetroStation abierto en la red (anuncios UDP en el puerto 55436), muestra su nombre y estado (buscando partida, en una sala, jugando) y permite conectarse también escribiendo la IP.
- **Solicitudes de conexión**: "Player02 quiere conectarse contigo", con Aceptar o Rechazar. Quien acepta es el anfitrión (jugador 1).
- **Sala LAN**: los dos jugadores con su estado Listo/Esperando. El anfitrión elige la experiencia entre los juegos que tenéis los dos y pulsa Empezar; los dos teléfonos abren el juego a la vez. Al salir del juego se vuelve a la sala.
- **Juego compartido (NES, SNES, PS1)**: los dos teléfonos ejecutan el mismo juego fotograma a fotograma y solo se envían las pulsaciones (UDP, con 3 fotogramas de margen y cada pulsación repetida en varios paquetes, así que una pérdida en la Wi-Fi no para el juego). Al empezar, el anfitrión envía su estado. Cada 5 s se compara una huella del estado de los dos y, si no coincide, el anfitrión reenvía el suyo y se corrige solo. El invitado usa las opciones de núcleo del anfitrión, y sus partidas guardadas no se tocan.
- **Pokémon de GBA (3.ª generación)**: intercambios y combates con el núcleo **gpSP** (GPL-2.0, commit 5819380), que emula el Adaptador Inalámbrico (Rojo Fuego, Verde Hoja, Esmeralda) y el cable link (Rubí, Zafiro) por la red. Cada jugador usa su juego y **su propia partida guardada** (la misma que con mGBA). El resto del tiempo la GBA sigue usando mGBA.
- Durante el multijugador se desactivan el rebobinado, el avance rápido, la carga de estados y el reinicio, porque los dos teléfonos tienen que seguir el mismo juego. Se ve el jugador (J1/J2), la latencia y avisos como "Esperando a Player02…" o "Player02 ha pausado el juego". Si se corta la conexión, sigues jugando solo.
- **Probado en el Galaxy A13** con dos instancias del motor conectadas entre sí: Super Mario Bros. 3 (NES) y Kirby's Dream Land 3 (SNES) a 60 FPS sin desincronizarse con pulsaciones aleatorias distintas en cada lado. También se comprobó la corrección automática con una desincronización forzada (se recupera en unos 30 ms), y el link de gpSP con Pokémon Esmeralda (conexión y sesión de link a 60 FPS).
- **Tutorial**: paso nuevo "¡Nuevo! Multijugador LAN". Quien ya había hecho el tutorial ve una sola vez el aviso **Novedades de la 3.0.0**, con un botón para probar el multijugador.
- Inicio: la tarjeta "Próximamente" del multijugador pasa a "Nuevo" y abre la sección. Un acceso directo "Multijugador" sustituye a "Consolas", que ya está en la barra inferior.
- **Autoría**: "por Jose Cruz" en la pantalla de carga, en el tutorial y en Ajustes > Acerca de.
- Herramienta de prueba `native/tools/netplay_test.cpp` (`-DRS_BUILD_TOOLS=ON`), que no se incluye en la app.

### Corregido
- **Editor de controles de PSP**: PSP aparece en el editor y tiene su propio diseño, con el joystick. Antes no se podía elegir, y sus botones compartían los ajustes de GBA.
- La versión de Ajustes > Acerca de y la de la cabecera de Inicio (antes ponía "V2.0" escrito a mano) salen de una sola constante (`lib/app/version.dart`).
- Si el otro jugador salía de la sala durante una partida, se cerraba también la pantalla del juego. Ahora solo se cierra la sala, y al terminar la partida se vuelve a Multijugador.

## Descubrir: todo se descarga desde la app y filtro "En español"
- **Navegador integrado** (`flutter_inappwebview` 6.1.5) para las fuentes que entregan el archivo desde su web (itch.io): el usuario pulsa el botón de la página (paga, dona o elige "No thanks") y RetroStation recoge el archivo, lo pasa al gestor de descargas y lo valida igual que el resto. Verificado: "Mariano versus Zombies" (GBA) descargado desde itch.io y jugado a 59,8 FPS.
- La disponibilidad "Solo enlace" pasa a "Desde su página": ya no hay resultados que no se puedan descargar.
- **Filtro "En español"**: usa el filtro de idioma oficial de itch.io (`/games/lang-es/`). Homebrew Hub no publica el idioma, así que se excluye y se avisa en pantalla.
- itch.io cubre ahora GBA, Game Boy (juegos de GB Studio), NES y SNES. Los feeds se piden en paralelo y escalonados, con un tiempo máximo de espera más corto.
- SNES añadido al filtro de consola.
- `third_party/flutter_inappwebview_android`: copia del plugin con un cambio de una línea para que compile con el Android Gradle Plugin actual (ver `third_party/README.md`).

## Etapa 9: cierre y entrega
- **APK release** (arm64-v8a) generado y probado: arranque en frío en torno a 1 s en el emulador.
- **Licencias**: Ajustes > Acerca de muestra la licencia y el commit exacto de los cinco núcleos (mGBA, FCEUmm, Snes9x, PCSX ReARMed, melonDS).
- **Opciones de núcleo**: el frontend ahora entiende `SET_VARIABLES` y responde con el valor por defecto que declara cada núcleo. Antes respondía "sin valor" y algunos núcleos (melonDS) se quedaban con valores internos distintos de sus valores por defecto documentados.
- **Rebobinado con presupuesto de memoria** (96 MB): en DS y PS1 cada instantánea ocupa varios MB, así que el historial se acorta en lugar de disparar la RAM.
- **Vertical con juegos altos**: la imagen del juego ocupa como máximo el 58 % del alto, así que los controles de DS ya no se solapan.
- **PSP** queda marcada como **No disponible**, con su motivo visible en la app: PPSSPP necesita OpenGL ES por hardware y el frontend dibuja por software.
- La pantalla de Ajustes ya no dice "Etapa 1 de 9".
- iOS: ver `docs/LIMITACIONES.md`. El código Dart es multiplataforma, pero el frontend nativo usa APIs de Android (ANativeWindow, AAudio) y necesita su capa para iOS, que se compila en un Mac o en CI.

## Etapa 8: nuevas consolas

### PlayStation (PCSX ReARMed, GPL-2.0, commit 7b0e8f8f)
- Dynarec ari64 en ARM y lightrec en x86_64. Formatos: `.cue` + `.bin`, `.chd`, `.pbp` y `.exe` (PS-X EXE).
- Al importar se validan las firmas y las pistas del `.cue` (rutas con `/` o `\` se rechazan), y la SHA-1 se calcula por bloques.
- Verificado con un PS-X EXE de prueba propio (`test/fixtures/psx`) a 60 FPS con el BIOS HLE.
- Controles: rombo con △ ○ ✕ □.

### Nintendo DS (melonDS, GPL-3.0, commit fab81072)
- JIT en arm64 y x86_64, renderizador por software, FreeBIOS integrado.
- Pantalla táctil: al tocar la pantalla inferior se envían coordenadas reales al núcleo (RETRO_DEVICE_POINTER).
- Se valida el CRC-16 de la cabecera. Verificado con un `.nds` de prueba propio (`test/fixtures/nds`, generado con `make_nds_test.ps1`): las dos pantallas cambian de color a 59,8 FPS, y los estados guardados funcionan (6,5 MB).
- Homebrew probados: GodMode9i y ftpd arrancan a ~60 FPS pero se quedan en blanco con FreeBIOS (ver LIMITACIONES).

### Corregido
- Los ajustes personalizados del botón A ya no deforman el rombo de SNES/PS1/DS: cada diseño se guarda por familia de consola.

### Verificado en el emulador
- **Game Boy / Game Boy Color** con mGBA (ya incluido): `totp-gb` (MIT) y `dont-cross-the-bridge` (GBC) a 59,7-59,9 FPS. Se valida la cabecera (checksum en 0x14D) y el indicador CGB de 0x143 decide entre GB y GBC.
- **NES** con FCEUmm (GPL-2.0, fijado al commit del 2026-11-02): "Treasure Hunt" descargado desde Descubrir y jugado a 60,3 FPS, con START funcionando. Se valida la cabecera iNES.
- **SNES** con Snes9x (licencia no comercial, fijado al commit del 2026-09-19): ROMs de prueba `undisbeliever/snes-test-roms` (Zlib) a 60,1 FPS, con controles A/B/X/Y en rombo y L/R. Se valida la cabecera LoROM, HiROM o ExHiROM, con o sin cabecera de copiadora.
- Corregido: un aviso con acción se quedaba fijo y tapaba START/SELECT dentro del juego.


## Etapa 7: funciones avanzadas

### Terminado y verificado en el emulador
- **Editor de controles** (Ajustes > Controles táctiles):
  - cada botón se arrastra y se redimensiona (50-200 %), con un diseño para vertical y otro para horizontal;
  - se puede restablecer un botón o todos;
  - se guarda de forma proporcional (fracciones del área), así que vale para cualquier tamaño de pantalla;
  - ningún control puede quedar fuera del área.
  Verificado: botón A movido en el editor y en su nueva posición dentro del juego.
- **Ajustes por consola** (Consolas > ⚙ en GBA): opciones reales del núcleo mGBA, con claves, valores y valores por defecto tomados de su código:
  - usar BIOS y saltar su intro;
  - saltar fotogramas;
  - optimizar bucles de espera;
  - filtro de audio;
  - direcciones opuestas.
  El frontend responde ahora a `GET_VARIABLE` y avisa al núcleo de los cambios durante la partida (`GET_VARIABLE_UPDATE`). Las opciones marcadas ↻ se aplican al reabrir el juego.
- **Copias de seguridad** (Ajustes > Copias de seguridad):
  - exporta las partidas del cartucho y los save states a un ZIP, en la carpeta que elija el usuario;
  - restaurar solo acepta rutas con el formato exacto `saves/<sha1>.srm` y `states/<sha1>/slotN.state|png`;
  - nada se ejecuta y la escritura es atómica;
  - los save states se vinculan a los juegos por SHA-1, así que la copia sirve en otra instalación.
  Verificado: ZIP real en Descargas con su manifiesto, 2 partidas y 1 estado con miniatura.
- **Liberar espacio**: borra solo datos regenerables (caché de metadatos y copias `.bak`).
- Ya hechas en etapas anteriores: avance rápido, rebobinado, filtros de imagen y mandos físicos.

### Pruebas
- `flutter test`: 64 pruebas correctas. Las nuevas cubren:
  - copia de seguridad entre dos instalaciones;
  - copia maliciosa con `../`, rutas no permitidas y ranuras inválidas: todo ignorado y nada escrito fuera;
  - archivo que no es una copia;
  - personalización de controles: mover, escalar, recolocar dentro del área, ids estables y guardar/recuperar;
  - opciones de núcleo válidas e inválidas.

### No implementado
- **Idioma de la interfaz**: la app solo está en español. Traducirla exige extraer todos los textos (internacionalización completa). No se muestra un selector de idioma que no haría nada.
- Restaurar una copia no se ha probado en el emulador, solo con pruebas automáticas (incluido entre dos instalaciones).

## Etapas 5 y 6: Game Discovery y gestor de descargas

### Fuentes investigadas (contra los servidores reales, no supuestas)
| Fuente | Uso en la app | Motivo |
|---|---|---|
| **Homebrew Hub** (`hh3.gbdev.io`) | Búsqueda + **descarga** (GB, GBC, GBA, NES) | API pública. Su aviso legal dice que todo lo que aloja es software libre y que no aloja material comercial con copyright; retira entradas a petición del autor. Se muestra la licencia de cada entrada y, si no la tiene, **se pide confirmación** antes de descargar. |
| **itch.io** | **Solo ficha y enlace** (GBA) | Feed RSS público de la etiqueta `gameboy-advance`. Descargar exige comprar o aceptar en su web. |
| Internet Archive | **Descartada** | Su campo de licencia lo rellena quien sube el archivo: hay volcados **comerciales** de GBA marcados como CC0 o dominio público. Usarla iría contra la regla de no distribuir ROMs comerciales. |

Detalles comprobados: el parámetro de búsqueda que de verdad funciona es `q` (parcial y sin distinguir mayúsculas); el `title` documentado distingue mayúsculas en el servidor real. Los archivos se sirven en `/static/<basepath>/entries/<slug>/<archivo>`, y el servidor admite `Range` (respuesta 206, necesaria para reanudar descargas).

### Terminado y verificado en el emulador
- **Arquitectura de adaptadores** (`discovery/`): `SourceAdapter` + un adaptador por fuente + un registro. Añadir o quitar una fuente no toca el resto. Cada fuente se activa o desactiva en Ajustes.
- **Descubrir**:
  - búsqueda por nombre y filtros de consola, género (etiqueta), año y disponibilidad (descargable o solo enlace);
  - todas las fuentes se consultan en paralelo; si una falla, se avisa y se muestran las demás;
  - paginación y carátulas.
  Verificado con resultados reales (DICEBITS, totp-gba, Dare To Doku…).
- **Ficha de resultado**:
  - procedencia con enlace verificable (carpeta de la entrada en GitHub);
  - licencia declarada o aviso de que no la hay;
  - aviso si es comercial (demo gratuita o precio);
  - capturas y descripción;
  - "Descargar", "Guardar en Pendientes" y "Abrir página original".
- **Gestor de descargas** (`download_manager/`, sobre `background_downloader`):
  - Android: WorkManager (continúa en segundo plano) y notificación con barra de progreso;
  - progreso, tamaño, velocidad y tiempo restante; pausar, reanudar, cancelar, reintentar y quitar del historial;
  - reintentos automáticos (3); evita duplicados;
  - las tareas sobreviven al cierre de la app;
  - al arrancar se borran los archivos parciales huérfanos.
- **Al terminar una descarga**:
  - se verifica el hash si la fuente lo publica, la cabecera y el contenido de los ZIP;
  - se comprueba que no esté repetido en la biblioteca;
  - el juego pendiente pasa a instalado y el temporal se borra siempre.
  Verificado: descarga real de `totp-gba.gba` (40 324 bytes, igual que en el servidor), carpeta `downloads/` vacía al terminar, juego jugable y con la portada sacada de la captura de la fuente.
- **Migración de base de datos v2 → v3** (`remoteId`, `downloadUrl`): verificada conservando los datos.
- Permisos de Android: `INTERNET` (faltaba en release: sin él, las descargas habrían fallado en la versión final) y `POST_NOTIFICATIONS` (se pide al primer uso; verificado).

### Errores encontrados y corregidos al probar con un juego real
- **Pulsaciones perdidas**: un toque más corto que un fotograma (16,7 ms) podía no llegar al juego. Ahora cada pulsación nueva se retiene hasta que el núcleo ejecuta un fotograma completo. Verificado con 6 toques de 4 a 16 ms; todos registrados.
- **El rebobinado no se activaba**: el `Tooltip` del botón competía con la pulsación larga. Verificado ahora: con 57 instantáneas, rebobina unos 9,5 s y vuelve a la pantalla de arranque del juego.
- **Tiempo jugado perdido si la app se cierra de golpe**: ahora se guarda cada minuto, al pasar a segundo plano y al salir.

### Pruebas
- `flutter test`: 56 pruebas correctas. Las nuevas cubren:
  - los adaptadores, con respuestas reales capturadas;
  - la URL de búsqueda;
  - el parseo de archivos, capturas y desarrolladores en sus tres formatos;
  - itch solo como enlace;
  - el servicio combinado tolerando una fuente caída;
  - el filtro de disponibilidad;
  - descargas: ZIP, hash incorrecto, duplicado y archivo corrupto.

### No verificado / limitaciones
- **Pausar y reanudar** no se ha podido probar en el emulador: las descargas de Homebrew Hub pesan pocos KB y terminan al instante. El servidor admite `Range` (comprobado) y la lógica la aporta `background_downloader`.
- **Filtro por idioma**: ninguna de las fuentes publica el idioma de sus juegos, así que no se ofrece. No sería un filtro real.
- El filtro de año se aplica a los resultados cargados (las fuentes no lo admiten en su API).
- No hay fuentes autorizadas con descarga para SNES, PS1, DS ni PSP.

## Etapa 4: biblioteca e importación local

### Terminado y verificado
- **Importar desde el teléfono** (botón "Importar" de la Biblioteca, selector de archivos del sistema): varios archivos a la vez, ROMs sueltos o ZIP. Verificado en el emulador con un ZIP real descargado: se importó el ROM y se ignoró el `.txt`.
- **Seguridad en la importación** (`game_library/rom_importer.dart`):
  - solo extensiones de consolas conocidas y cabecera válida;
  - de un ZIP solo se usa el nombre base de cada entrada (protección **zip-slip**, probada con `../../../evil.gba`);
  - límites de tamaño por entrada y totales (protección contra *zip bombs*);
  - ZIP dañados y archivos falsos se rechazan con su motivo;
  - duplicados por SHA-1 descartados;
  - nombres saneados y sin sobrescribir archivos existentes (`juego (2).gba`);
  - nada se ejecuta.
- **Informe de importación**: lista de descartados con su motivo y aviso de usar solo copias propias.
- **Identificación con No-Intro** (`metadata/`): la app descarga y guarda las bases públicas de libretro-database (No-Intro, género y año; 1,5 MB para GBA) y busca el SHA-1 del ROM. Si coincide, pone el nombre oficial, el género y el año, y marca el juego como **Verificado**. Si no, avisa de que puede ser homebrew, un hack o un volcado modificado (verificado en el emulador).
- **Portadas** desde libretro-thumbnails (`Named_Boxarts`), validando que sean PNG reales. URL comprobada con un juego real (HTTP 200, PNG de 437 KB).
- **Ficha del juego**: portada, consola, verificado, género, año, Jugar, identificar, save states del juego, tiempo jugado, última partida, tamaño, procedencia y SHA-1. Se puede renombrar, poner en favoritos y eliminar (con opción de borrar también partidas y estados).
- **BIOS de GBA opcional**: se instala desde Ajustes y solo se acepta el volcado oficial (tamaño y SHA-1 comprobados con libretro `System.dat`). mGBA la usa automáticamente si existe.
- **Migración de base de datos v1 → v2** (columna `verified`): verificada instalando encima de la versión anterior; los juegos se conservaron.

### Pruebas
- `flutter test`: 46 pruebas correctas. Las nuevas cubren el parser de DAT con extractos reales, el índice combinado, los nombres de portada, la importación de ROM suelto y ZIP, zip-slip, duplicados, falsos, ZIP dañado o vacío, nombres repetidos y saneado de nombres.
- Errores encontrados y corregidos:
  - la API de `file_picker` 13 cambió (métodos estáticos);
  - la compilación incremental de Kotlin falla en Windows con proyecto y caché en discos distintos (`kotlin.incremental=false`);
  - una edición con PowerShell corrompió tildes de un archivo (corregido; desde entonces solo se edita con herramientas UTF-8).

### Pendiente / no verificado
- La identificación positiva (un juego que sí está en No-Intro) está cubierta por pruebas con datos reales y por la URL comprobada, pero no se ha hecho en el emulador porque no hay ningún ROM comercial disponible para probar.
- Importar BIOS no se ha probado en el emulador (no hay un volcado de BIOS disponible).

## Etapa 3: audio, controles táctiles y save states

### Terminado y verificado (emulador Android x86_64, API 37)
- **Audio con AAudio** (baja latencia, `native/frontend/audio_output.cpp`): buffer circular sin bloqueos, remuestreo lineal de 32 768 Hz a la frecuencia del dispositivo (48 000 Hz en el emulador) y control dinámico de velocidad (±0,5 % según el llenado del buffer) para evitar cortes. Hay volumen; el audio se silencia en avance rápido y rebobinado, y se pausa con el juego. Log: `Audio: 32768 Hz -> 48000 Hz, buffer 4360 frames`. *minSdk sube a 26 (Android 8.0) por AAudio.*
- **Controles táctiles multitáctiles**: cruceta con diagonales y zona muerta, A, B, L, R, Start y Select. Un dedo puede deslizarse entre botones, con vibración al pulsar y opacidad y tamaño configurables. En vertical van bajo la imagen; en horizontal, en franjas laterales que nunca tapan la imagen. Verificado en el log nativo: A = `0x100`, B = `0x001`, Start = `0x008`, y el deslizamiento por la cruceta da arriba → arriba+derecha (`0x090`) → derecha.
- **Save states**: 6 ranuras por juego, con miniatura PNG, fecha y copia de seguridad `.bak` de la versión anterior al sobrescribir. Escritura atómica. Verificado: `slot1.state` (528 KB) + `slot1.png`, carga correcta ("Ranura 1 cargada"). Desde "Partidas" se puede abrir un juego directamente en una ranura.
- **Menú rápido** (pausa el juego): guardar y cargar ranuras, reiniciar y salir.
- **Avance rápido** ×2/×3/×4: verificado a 178,7 FPS con ×3.
- **Rebobinado** (adelantado de la Etapa 7), mientras se mantiene pulsado ⏪: instantáneas en memoria cada 10 fotogramas (20 s) y reproducción hacia atrás a unas 3 veces la velocidad normal. *Implementado y estable, pero no verificado visualmente (los ROMs de prueba muestran una imagen fija).*
- **Filtros de imagen** (adelantado de la Etapa 7): nítido, suavizado, líneas CRT y rejilla LCD.
- **Orientación**: automática, vertical u horizontal.
- **Ajustes nuevos**: volumen, opacidad y tamaño de controles, vibración, orientación, filtro, velocidad del avance rápido, rebobinado y mostrar FPS.

### Pruebas
- `flutter test`: 37 pruebas correctas. Las nuevas cubren la geometría de los controles: dentro del área, sin solapes, sin tapar la imagen en horizontal, cada botón, diagonales, multitáctil y escala.
- Error encontrado y corregido: en horizontal la imagen ocupaba toda la altura y los controles y la barra quedaban encima (iconos invisibles).

### Pendiente
- Editor de posición de los controles y ajustes por consola (Etapa 7).
- Comprobar el rebobinado con un juego en movimiento.

## Etapa 2: mGBA integrado, un juego GBA se ejecuta

### Terminado y verificado
- **mGBA 0.10.5** (MPL-2.0) en `native/third_party/mgba`, compilado como núcleo libretro (`libmgba_libretro.so`) para arm64-v8a, armeabi-v7a y x86_64 con NDK 30 y CMake 3.31.6, integrado en Gradle.
- **Frontend libretro propio en C++** (`native/frontend/rs_frontend.cpp`):
  - carga el núcleo con `dlopen`;
  - ejecuta `retro_run()` en un hilo propio a la frecuencia real de la GBA (59,7275 Hz);
  - convierte el vídeo de RGB565, 0RGB1555 o XRGB8888 a RGBA y lo escribe directamente en un `ANativeWindow`.
- **Vídeo**: Flutter lo muestra con un `Texture` mediante `SurfaceProducer`. No se copian fotogramas a Dart. Los píxeles se ven nítidos al escalar.
- **API C mediante Dart FFI**: cargar, arrancar, pausar, reiniciar, botones, FPS, guardar SRAM y descargar.
- **Pantalla de juego**:
  - contador de FPS medido por el hilo nativo;
  - pausar/reanudar y reiniciar;
  - pantalla completa;
  - controles por teclado y por mando físico (flechas, X/Z = A/B, A/S = L/R, Enter = Start, Retroceso = Select; botones de mando estándar).
- **Ciclo de vida**: en segundo plano se pausa el núcleo y se guarda la SRAM. Al salir del juego se guarda la SRAM y se descarga el núcleo.
- **SRAM persistente**: se carga al empezar y se guarda de forma atómica (archivo temporal + rename) al pausar, al salir y cada ~10 s si cambió. Así se evita perder progreso si la app se cierra de golpe.
- **Detección automática de ROMs** (adelantado de la Etapa 4):
  - escanea la carpeta privada `roms/` al iniciar y con el botón ↻ de la Biblioteca;
  - valida la cabecera GBA (byte fijo 0x96 y checksum);
  - calcula el SHA-1 en un isolate, evita duplicados y rechaza archivos de otras consolas o con extensiones desconocidas.
- **Tiempo jugado y "Continuar jugando"**: cada sesión actualiza la fecha de la última partida y suma el tiempo jugado.
- Licencia de mGBA visible en Ajustes > Acerca de > Licencias.

### Pruebas
- `flutter analyze`: sin problemas.
- `flutter test`: 26 pruebas correctas. Las nuevas cubren la validación de cabecera con ROMs reales, ROMs alterados o falsos, el escáner y los duplicados.
- En el emulador de Android (x86_64, API 37), con los ROMs de prueba [gba-tests](https://github.com/jsmolka/gba-tests) (MIT):

  | ROM | Resultado | FPS |
  |---|---|---|
  | memory | All tests passed | 59,6-59,8 |
  | arm | Falla la prueba 235 | 59,7 |
  | thumb | Falla la prueba 230 | 59,7 |
  | bios | Falla la prueba 001 | 59,8 |

  Qué significa cada fallo:
  - **Prueba 102 de thumb (overflow de suma): corregido.** Con `-O2`, clang eliminaba el cálculo del flag V porque mGBA usa aritmética con signo que desborda. Se compila el núcleo con `-fwrapv`. Antes fallaba en la 102 y ahora pasa todas hasta la 230.
  - **arm 235** ("CMP/TST con destino PC no vacía el pipeline") y **thumb 230** ("STM con la base en la lista"): casos límite que mGBA 0.10.5 no cumple. Dan el mismo resultado con -O0 y -O2, así que vienen del núcleo y no de la integración.
  - **bios 001**: necesita el BIOS oficial de Nintendo. Se usa el BIOS emulado (HLE) de mGBA; ver `LIMITACIONES.md`.
- En segundo plano el proceso usa 0 % de CPU (núcleo pausado). Al volver, sigue a 59,8 FPS.
- Errores encontrados y corregidos: el tiempo jugado no se guardaba (en Riverpod 3 se usaba `ref` dentro de `dispose()`), y todos los ROMs de prueba se llamaban igual (ahora el título sale del nombre de archivo).

### Pendiente
- **Audio**: el núcleo genera sonido, pero todavía no se reproduce (Etapa 3).
- **Controles táctiles**: en un teléfono sin mando no se puede jugar todavía (Etapa 3).
- Save states (Etapa 3). Filtros gráficos y avance rápido (Etapa 7).
- Importar ROMs desde el teléfono con el selector de archivos (Etapa 4). Por ahora los ROMs se copian a la carpeta privada con `adb`.
- Solo se ha probado en el emulador x86_64. El rendimiento en un teléfono ARM de gama media no está medido.
- iOS no tiene todavía el frontend nativo (Etapa 9).

## Etapa 1: proyecto, estructura, navegación y diseño

### Terminado y verificado
- Proyecto Flutter 3.50 / Dart 3.14 para Android e iOS (`com.moran.retrostation`).
- Arquitectura por módulos (ver `ARQUITECTURA.md`).
- **Tema oscuro** con fondo gris carbón o negro AMOLED y acento violeta o azul, tarjetas y transiciones suaves.
- **Navegación** con go_router: barra inferior (Inicio, Descubrir, Biblioteca, Partidas, Ajustes) que conserva el estado de cada pestaña; Consolas y Reproductor como pantallas completas.
- **Base de datos SQLite** (drift): tablas `games`, `save_states` y `setting_entries`, con claves foráneas y SHA-1 único.
- **Biblioteca**: categorías Todos, Instalados, Favoritos, Recientes y Pendientes; filtro por consola; marcar y desmarcar favoritos; contenido reactivo a la base de datos.
- **Inicio**: contador de juegos, favoritos y núcleos listos, juegos recientes y acceso a las consolas.
- **Consolas**: registro de las 8 consolas previstas con su núcleo, licencia, extensiones, estado y etapa de integración.
- **Partidas guardadas**: listado de save states con su juego, y borrado con confirmación (registro y archivos).
- **Ajustes persistentes**: fondo, acento y animaciones reducidas; uso real de cada carpeta privada calculado en un isolate aparte; licencias de terceros.
- **Almacenamiento privado**: `roms`, `saves`, `states`, `covers` y `downloads`, con validación de que ninguna ruta salga del directorio de la app.
- Nombre visible "RetroStation" en Android e iOS.

### Pruebas
- `flutter analyze`: sin problemas.
- `flutter test`: 16 pruebas correctas.
  - Base de datos: orden, filtros por categoría y consola, favoritos, recientes, duplicados por SHA-1, contador, borrado en cascada de save states, persistencia de ajustes.
  - Registro de consolas: ids y extensiones únicas, normalización de extensiones.
  - Almacenamiento: creación de carpetas, cálculo de espacio, rechazo de rutas que salen del directorio (`..`).
  - Widgets, con pantalla de teléfono de 360×780 dp: navegación por las 5 pestañas, Consolas, biblioteca filtrada y cambio de acento aplicado y guardado.
- En el emulador de Android Studio (Medium Phone, API 37): la app arranca, muestra Inicio y Ajustes, y el fondo AMOLED y el acento azul se mantienen después de cerrarla y volver a abrirla.
- Errores encontrados y corregidos gracias a las pruebas: tres desbordes de diseño en pantallas de 360 dp (estado vacío de Inicio, tarjetas de consola, cabecera) y el chip de filtro de consola, que quedaba oculto al desplazar las categorías.

### Pendiente (y en qué etapa se resuelve)
- Pantalla de juego con emulación: Etapa 2. Hoy el Reproductor indica que el núcleo de GBA está en integración.
- Crear save states y SRAM: Etapa 3.
- Importar ROMs: Etapa 4. Mientras tanto la biblioteca solo puede estar vacía y lo explica.
- Búsqueda en Descubrir: Etapa 5. La pantalla solo informa de las fuentes previstas; no tiene búsqueda ni botones sin función.
- Ajustes de idioma, audio, controles, renderizador, filtros y orientación: se añadirán cuando haya algo que configurar (Etapas 2, 3 y 7).
- Icono propio de la app: pendiente (por ahora usa el de Flutter).
