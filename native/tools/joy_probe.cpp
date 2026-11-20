// Lista los mandos que ve Windows (API winmm) y su estado actual:
//   joy_probe [segundos]   (con segundos > 0, muestra los cambios mientras tanto)
#include <windows.h>
#include <mmsystem.h>

#include <cstdio>
#include <cstdlib>

int main(int argc, char** argv) {
  const int seconds = argc > 1 ? atoi(argv[1]) : 0;
  const UINT n = joyGetNumDevs();
  printf("ranuras: %u\n", n);
  JOYINFOEX last[16]{};
  for (UINT i = 0; i < n && i < 16; ++i) {
    JOYINFOEX info{sizeof(info), JOY_RETURNALL};
    if (joyGetPosEx(i, &info) != JOYERR_NOERROR) continue;
    JOYCAPSW caps{};
    joyGetDevCapsW(i, &caps, sizeof(caps));
    wprintf(L"[%u] '%ls' vid=%04x pid=%04x botones=%u ejes=%u pov=%s\n", i, caps.szPname, caps.wMid, caps.wPid,
            caps.wNumButtons, caps.wNumAxes, (caps.wCaps & JOYCAPS_HASPOV) ? L"sí" : L"no");
    printf("    x=%lu y=%lu z=%lu r=%lu u=%lu v=%lu pov=%lu botones=0x%lx\n", info.dwXpos, info.dwYpos, info.dwZpos,
           info.dwRpos, info.dwUpos, info.dwVpos, info.dwPOV, info.dwButtons);
    last[i] = info;
  }
  for (int t = 0; t < seconds * 100; ++t) {
    Sleep(10);
    for (UINT i = 0; i < n && i < 16; ++i) {
      JOYINFOEX info{sizeof(info), JOY_RETURNALL};
      if (joyGetPosEx(i, &info) != JOYERR_NOERROR) continue;
      if (info.dwButtons != last[i].dwButtons || info.dwPOV != last[i].dwPOV) {
        printf("[%u] botones=0x%lx pov=%lu\n", i, info.dwButtons, info.dwPOV);
        fflush(stdout);
      }
      last[i] = info;
    }
  }
  return 0;
}
