"""Genera native/cores/mupen64plus_sources.cmake a partir del Makefile.common
de Mupen64Plus-Next (las listas de archivos incondicionales).

    python tool/gen_mupen64plus_sources.py
"""
import os

ROOT = os.path.join(os.path.dirname(__file__), '..')
MK = os.path.join(ROOT, 'native', 'third_party', 'mupen64plus', 'Makefile.common')
OUT = os.path.join(ROOT, 'native', 'cores', 'mupen64plus_sources.cmake')

text = open(MK, encoding='utf-8').read()


def files_after(marker, start=0):
    """Lista de rutas que siguen a `marker` (una por línea) hasta la primera que no lo es."""
    i = text.index(marker, start)
    out = []
    for line in text[i:].splitlines()[1:]:
        t = line.strip().rstrip('\\').strip()
        if not t.startswith('$('):
            break
        out.append(t)
    return out, i


core, _ = files_after('SOURCES_C = \\')
glide, i = files_after('SOURCES_CXX   += \\')
hq, _ = files_after('SOURCES_CXX   += \\', i + 10)
lr, _ = files_after('SOURCES_C += $(LIBRETRO_DIR)/libretro.c \\')
lr = ['$(LIBRETRO_DIR)/libretro.c'] + lr
rsp, _ = files_after('SOURCES_C += \\\n\t$(RSPDIR)/src/alist.c')

REPL = [
    ('$(CORE_DIR)', '${M64_CORE}'),
    ('$(VIDEODIR_GLIDEN64)', '${M64}/GLideN64'),
    ('$(LIBRETRO_COMM_DIR)', '${M64}/libretro-common'),
    ('$(LIBRETRO_DIR)', '${M64}/libretro'),
    ('$(AUDIO_LIBRETRO_DIR)', '${M64}/custom/mupen64plus-core/plugin/audio_libretro'),
    ('$(RSPDIR)', '${M64}/mupen64plus-rsp-hle'),
    ('$(ROOT_DIR)', '${M64}'),
]


def conv(lst):
    out = []
    for x in lst:
        for a, b in REPL:
            x = x.replace(a, b)
        assert '$(' not in x, x
        out.append('  ' + x)
    return '\n'.join(out)


with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
    f.write('# Generado por tool/gen_mupen64plus_sources.py desde\n'
            '# third_party/mupen64plus/Makefile.common. No editar a mano.\n')
    f.write('set(M64_SRC_CORE\n' + conv(core) + '\n)\n')
    f.write('set(M64_SRC_GLIDE\n' + conv(glide + hq) + '\n)\n')
    f.write('set(M64_SRC_LIBRETRO\n' + conv(lr) + '\n)\n')
    f.write('set(M64_SRC_RSP\n' + conv(rsp) + '\n)\n')
print(len(core), len(glide), len(hq), len(lr), len(rsp))
