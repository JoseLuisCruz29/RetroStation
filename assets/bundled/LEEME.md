# Juegos incluidos en el APK

Todo lo que pongas en esta carpeta aparece en la Biblioteca nada más instalar
la app (en el primer arranque). Después de añadir o quitar archivos hay que
volver a compilar el APK.

- **Formatos:** `.gba`, `.gb`, `.gbc`, `.nes`, `.sfc`, `.smc`, `.nds`, `.exe` (PS1) y `.zip`.
  Los discos de PS1 en `.cue` + `.bin` no se admiten aquí; usa `.chd`/`.pbp` o importa aparte.
- **Validación:** cada archivo se comprueba igual que al importar (cabecera,
  tamaño, duplicados). Lo que no sea un ROM válido se descarta.
- **Una sola vez:** si borras un juego incluido, no vuelve a aparecer. Si una
  versión nueva del APK trae archivos nuevos, se añaden esos.
- **Datos (opcional):** en `bundled.json` puedes poner título, portada, autor,
  licencia y fuente de cada archivo. Sin entrada, se usa el nombre del archivo.
- **Espacio:** cada juego ocupa el doble (dentro del APK y en la biblioteca).
  Hasta unos 300–500 MB en total va bien.
- **Licencia:** solo juegos que se puedan redistribuir (homebrew con licencia
  libre o con permiso del autor). Los 6 incluidos vienen de Homebrew Hub, con
  la licencia y el código fuente indicados en `bundled.json`.
