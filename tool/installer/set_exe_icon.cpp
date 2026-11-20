// Cambia el icono de un .exe por el de un archivo .ico:
//   set_exe_icon <programa.exe> <icono.ico>
// Se usa con el instalador de IExpress, que no permite elegir icono. Solo se
// tocan los recursos de icono; el resto (el paquete con la app) se conserva.
#include <windows.h>

#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#pragma pack(push, 2)
struct IconDirEntry {  // en el .ico
  BYTE width, height, colors, reserved;
  WORD planes, bits;
  DWORD size, offset;
};
struct GroupEntry {  // en RT_GROUP_ICON
  BYTE width, height, colors, reserved;
  WORD planes, bits;
  DWORD size;
  WORD id;
};
#pragma pack(pop)

static BOOL CALLBACK collect(HMODULE, LPCWSTR, LPWSTR name, LONG_PTR param) {
  auto* names = reinterpret_cast<std::vector<std::wstring>*>(param);
  names->push_back(IS_INTRESOURCE(name) ? L"#" + std::to_wstring(reinterpret_cast<ULONG_PTR>(name)) : name);
  return TRUE;
}

static LPCWSTR as_name(const std::wstring& n) {
  return n[0] == L'#' ? MAKEINTRESOURCEW(std::stoi(n.substr(1))) : n.c_str();
}

struct Existing {
  LPCWSTR type;
  std::wstring name;
  WORD lang;
};

static BOOL CALLBACK collect_lang(HMODULE, LPCWSTR, LPCWSTR, WORD lang, LONG_PTR param) {
  reinterpret_cast<std::vector<WORD>*>(param)->push_back(lang);
  return TRUE;
}

int wmain(int argc, wchar_t** argv) {
  if (argc != 3) {
    fwprintf(stderr, L"uso: set_exe_icon programa.exe icono.ico\n");
    return 2;
  }
  std::ifstream in(argv[2], std::ios::binary);
  std::vector<BYTE> ico((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  if (ico.size() < 6 || ico[2] != 1) {
    fwprintf(stderr, L"%s no es un .ico válido\n", argv[2]);
    return 1;
  }
  const WORD count = *reinterpret_cast<WORD*>(&ico[4]);

  // Iconos y grupos que tiene ahora el .exe (para quitarlos).
  std::vector<std::wstring> icons, groups;
  std::vector<Existing> existing;
  if (HMODULE mod = LoadLibraryExW(argv[1], nullptr, LOAD_LIBRARY_AS_DATAFILE)) {
    EnumResourceNamesW(mod, RT_ICON, collect, reinterpret_cast<LONG_PTR>(&icons));
    EnumResourceNamesW(mod, RT_GROUP_ICON, collect, reinterpret_cast<LONG_PTR>(&groups));
    for (auto [type, names] : {std::pair{RT_ICON, &icons}, std::pair{RT_GROUP_ICON, &groups}}) {
      for (const auto& n : *names) {
        std::vector<WORD> langs;
        EnumResourceLanguagesW(mod, type, as_name(n), collect_lang, reinterpret_cast<LONG_PTR>(&langs));
        for (WORD l : langs) existing.push_back({type, n, l});
      }
    }
    FreeLibrary(mod);
  }

  HANDLE update = BeginUpdateResourceW(argv[1], FALSE);
  if (!update) {
    fwprintf(stderr, L"No se puede abrir %s (error %lu)\n", argv[1], GetLastError());
    return 1;
  }
  const WORD lang = MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL);
  for (const auto& e : existing) UpdateResourceW(update, e.type, as_name(e.name), e.lang, nullptr, 0);

  std::vector<BYTE> group(6 + count * sizeof(GroupEntry));
  memcpy(group.data(), ico.data(), 6);
  for (WORD i = 0; i < count; ++i) {
    const auto* e = reinterpret_cast<IconDirEntry*>(&ico[6 + i * sizeof(IconDirEntry)]);
    const WORD id = static_cast<WORD>(i + 1);
    if (!UpdateResourceW(update, RT_ICON, MAKEINTRESOURCEW(id), lang, &ico[e->offset], e->size)) {
      fwprintf(stderr, L"No se pudo añadir el icono %u (error %lu)\n", id, GetLastError());
      EndUpdateResourceW(update, TRUE);
      return 1;
    }
    auto* g = reinterpret_cast<GroupEntry*>(&group[6 + i * sizeof(GroupEntry)]);
    memcpy(g, e, 12);
    g->id = id;
  }
  // El grupo con el nombre del original (o 1): es el que usa el Explorador.
  const std::wstring name = groups.empty() ? L"#1" : groups.front();
  if (!UpdateResourceW(update, RT_GROUP_ICON, as_name(name), lang, group.data(),
                       static_cast<DWORD>(group.size())) ||
      !EndUpdateResourceW(update, FALSE)) {
    fwprintf(stderr, L"No se pudo guardar (error %lu)\n", GetLastError());
    return 1;
  }
  wprintf(L"Icono cambiado (%u tamaños)\n", count);
  return 0;
}
