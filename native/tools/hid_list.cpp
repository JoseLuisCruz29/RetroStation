#include <windows.h>
#include <hidsdi.h>
#include <setupapi.h>
#include <cstdio>
#include <vector>
int main() {
  GUID guid; HidD_GetHidGuid(&guid);
  HDEVINFO set = SetupDiGetClassDevsW(&guid, nullptr, nullptr, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  SP_DEVICE_INTERFACE_DATA iface{sizeof(iface)};
  for (DWORD i = 0; SetupDiEnumDeviceInterfaces(set, nullptr, &guid, i, &iface); ++i) {
    DWORD size = 0;
    SetupDiGetDeviceInterfaceDetailW(set, &iface, nullptr, 0, &size, nullptr);
    std::vector<BYTE> buf(size);
    auto* d = reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(buf.data());
    d->cbSize = sizeof(*d);
    SetupDiGetDeviceInterfaceDetailW(set, &iface, d, size, nullptr, nullptr);
    HANDLE h = CreateFileW(d->DevicePath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
    HIDD_ATTRIBUTES a{sizeof(a)};
    BOOL ok = h != INVALID_HANDLE_VALUE && HidD_GetAttributes(h, &a);
    wprintf(L"%ls\n   abierto=%d vid=%04x pid=%04x err=%lu\n", d->DevicePath, h != INVALID_HANDLE_VALUE, ok ? a.VendorID : 0, ok ? a.ProductID : 0, GetLastError());
    if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
  }
}
