# Limitaciones conocidas y alternativas

| Limitación | Impacto | Alternativa |
|---|---|---|
| PSP no está disponible | No se pueden jugar `.iso` ni `.cso` de PSP | PPSSPP necesita un contexto OpenGL ES/Vulkan por hardware. Habría que añadir al frontend un renderizador GPU (EGL + `RETRO_ENVIRONMENT_SET_HW_RENDER`) |
| DS usa FreeBIOS (BIOS y firmware libres) | Programas sencillos funcionan (prueba propia a 59,8 FPS), pero homebrew más complejo (GodMode9i, ftpd) se queda en pantalla blanca. Es probable que también falle parte del catálogo | Colocar volcados propios `bios7.bin`, `bios9.bin` y `firmware.bin` en `system/`; melonDS los detecta. Todavía no hay una opción en la app para importarlos |
| PS1 usa el BIOS HLE de PCSX ReARMed | La mayoría de juegos arrancan; algunos necesitan el BIOS real | Colocar un volcado propio `scph1001.bin` en `system/` (no hay opción en la app para importarlo) |
| PS1: faltan L2, R2 y los sticks analógicos en los controles táctiles | Juegos que los usen solo se controlan con un mando físico | Añadirlos al diseño táctil |
| La importación de ZIP está limitada a 256 MB | Discos de PS1 comprimidos más grandes no se pueden importar en ZIP | Importar el `.cue` + `.bin` o un `.chd` directamente (hasta 1 GB) |
| Frontend nativo solo para Android | Hoy no hay versión de iOS | Portar la capa de vídeo y audio (CAMetalLayer/CVPixelBuffer y AudioUnit), enlazar los núcleos estáticamente y compilar en macOS o CI (Codemagic, GitHub Actions) |
| Para compilar en iOS hace falta macOS con Xcode; el desarrollo se hace en Windows | No se puede generar ni probar la app de iOS desde este PC | Compilar en CI (GitHub Actions o Codemagic con runners macOS) e instalar con AltStore/SideStore. Con una cuenta Apple gratuita, la firma caduca cada 7 días. Se prepara en la Etapa 9 |
| iOS no permite JIT | Sin efecto en GBA, GB, NES ni SNES. PS1 y PSP funcionarán con intérprete y serán más lentos | Núcleos en modo intérprete y ajustes de rendimiento por consola |
| iOS no permite cargar núcleos descargados | Los núcleos no se pueden actualizar por separado | Núcleos enlazados estáticamente en el binario |
| Las descargas en segundo plano de iOS las planifica el sistema | El progreso puede detenerse con la app cerrada | `URLSession` en segundo plano mediante `background_downloader`; se reanuda al volver |
| Pausar y reanudar una descarga requiere que el servidor soporte `Range` | No todas las fuentes lo permiten | Se detecta para cada descarga y se muestra al usuario |
| Sin el BIOS oficial de GBA se usa el BIOS emulado (HLE) de mGBA | La gran mayoría de juegos funcionan. Algunos detalles (la pantalla de arranque de Nintendo y lecturas directas del BIOS) no son exactos, y gba-tests/bios falla en la prueba 001 | Si el usuario tiene su propio volcado de BIOS (`gba_bios.bin`), se podrá colocar en `system/`; mGBA lo detecta. La opción para importarlo llega con la Etapa 4 |
| mGBA 0.10.5 no cumple dos casos límite de CPU (gba-tests arm 235 y thumb 230) | Instrucciones muy poco comunes; no se conocen juegos comerciales afectados | Actualizar a una versión posterior de mGBA cuando se publique y volver a pasar las pruebas |
| Solo se ha probado en el emulador de Android | No se ha medido el rendimiento en un teléfono físico | Probar en un dispositivo ARM antes de la Etapa 9 |
| Internet Archive no es fiable como fuente de descargas | Sus licencias las declara quien sube el archivo; hay ROMs comerciales marcados como CC0 | Descartada. Si se añade en el futuro, solo como enlace y con colecciones verificadas a mano |
| Algunas entradas de Homebrew Hub no declaran licencia | No consta una autorización expresa de redistribución | Se avisa y se pide confirmación antes de descargar; Homebrew Hub retira entradas a petición del autor |
| Homebrew Hub no publica el idioma de los juegos | El filtro "En español" solo busca en itch.io | Se avisa en pantalla. No se adivina el idioma por el título |
| El idioma de itch.io lo declara el autor | Algún juego marcado en español puede tener solo parte del texto traducido, o incluir varios idiomas | Es el dato oficial de la fuente; no hay otro mejor |
| itch.io agrupa por etiquetas (`nes`, `snes`...) | Algunos resultados son juegos de PC de estilo retro, no ROMs | Al descargar se valida la cabecera y se rechaza lo que no es un ROM |
| Pocas fuentes autorizadas para PS1 y DS | Descubrir ofrece juegos de GB, GBC, GBA, NES y SNES | Para el resto, importar copias propias |
| Snes9x tiene una licencia no comercial | Solo es compatible con un uso personal | Documentado; la app es personal |
| itch.io entrega el archivo desde su web (pagar, donar o "No thanks") | La descarga no es de un toque | Navegador integrado: el usuario pulsa el botón de la propia página y la app recoge el archivo. Los enlaces de itch.io caducan: "Reintentar" puede fallar y hay que volver a pulsar en la página |
