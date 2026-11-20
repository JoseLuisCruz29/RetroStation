"""Genera los efectos de sonido de la interfaz (estilo RetroStation OS).

Uso (desde la raíz del proyecto):
    python tool/make_ui_sounds.py

Son ondas cuadradas y triangulares sintetizadas, como los de la página
RetroStation OS (Web Audio), guardadas como WAV de 16 bits en
android/app/src/main/res/raw/ para que SoundPool los reproduzca sin retardo.
"""
import math
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / 'android/app/src/main/res/raw'


def osc(kind, phase):
    p = phase % 1.0
    if kind == 'square':
        return 1.0 if p < 0.5 else -1.0
    if kind == 'triangle':
        return 4 * abs(p - 0.5) - 1
    return math.sin(2 * math.pi * p)


def note(buf, freq, start, dur, kind='square', vol=0.25, to=None):
    """Suma una nota con ataque de 8 ms y caída exponencial."""
    n = int(dur * RATE)
    s0 = int(start * RATE)
    if len(buf) < s0 + n:
        buf.extend([0.0] * (s0 + n - len(buf)))
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq if to is None else freq * (to / freq) ** (t / dur)
        phase += f / RATE
        attack = min(1.0, t / 0.008)
        decay = math.exp(-5.5 * t / dur)
        buf[s0 + i] += osc(kind, phase) * vol * attack * decay


def save(name, buf):
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(1e-9, max(abs(x) for x in buf))
    gain = min(1.0, 0.9 / peak)
    with wave.open(str(OUT / f'{name}.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, x * gain)) * 32767)) for x in buf))
    print(f'{name}.wav  {len(buf) / RATE * 1000:.0f} ms')


def main():
    # Confirmar: dos notas ascendentes.
    b = []
    note(b, 660, 0, 0.06, vol=0.2)
    note(b, 990, 0.06, 0.08, vol=0.2)
    save('sfx_click', b)

    # Abrir / cambiar de sección: arpegio.
    b = []
    for i, f in enumerate([523, 659, 784, 1047]):
        note(b, f, i * 0.05, 0.08, kind='triangle', vol=0.25)
    save('sfx_open', b)

    # Volver / cerrar: dos notas descendentes.
    b = []
    note(b, 784, 0, 0.07, kind='triangle', vol=0.22)
    note(b, 523, 0.07, 0.1, kind='triangle', vol=0.22)
    save('sfx_back', b)

    # Cursor (botones pequeños, interruptores): blip corto.
    b = []
    note(b, 1320, 0, 0.035, vol=0.1)
    save('sfx_move', b)

    # Encendido: acorde ascendente (al abrir la app).
    b = []
    for i, f in enumerate([262, 330, 392, 523, 659]):
        note(b, f, i * 0.07, 0.22, vol=0.12)
    save('sfx_on', b)


if __name__ == '__main__':
    main()
