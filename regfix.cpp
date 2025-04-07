#include <Windows.h>
#include <string>

// 这个函数用于获取处理器名称，使用了正确的ANSI字符串版本
void get_processor_name(std::string& description) {
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
                    "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
                    0,
                    KEY_READ,
                    &hKey) == ERROR_SUCCESS) {
        DWORD cpu_brand_size = 0;
        if (RegQueryValueExA(hKey,
                            "ProcessorNameString",
                            NULL,
                            NULL,
                            NULL,
                            &cpu_brand_size) == ERROR_SUCCESS) {
            description.resize(cpu_brand_size);
            if (RegQueryValueExA(hKey,
                                "ProcessorNameString",
                                NULL,
                                NULL,
                                (LPBYTE)&description[0], // NOLINT
                                &cpu_brand_size) == ERROR_SUCCESS) {
                if (description.find('\0') != std::string::npos) {
                    description.resize(description.find('\0'));
                }
            }
        }
        RegCloseKey(hKey);
    }
} 