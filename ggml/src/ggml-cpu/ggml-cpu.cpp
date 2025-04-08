#ifdef _WIN32
        HKEY hKey;
        if (RegOpenKeyExW(HKEY_LOCAL_MACHINE,
                        L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
                        0,
                        KEY_READ,
                        &hKey) == ERROR_SUCCESS) {
            DWORD cpu_brand_size = 0;
            if (RegQueryValueExW(hKey,
                                L"ProcessorNameString",
                                NULL,
                                NULL,
                                NULL,
                                &cpu_brand_size) == ERROR_SUCCESS) {
                std::vector<wchar_t> wbuffer(cpu_brand_size / sizeof(wchar_t));
                if (RegQueryValueExW(hKey,
                                    L"ProcessorNameString",
                                    NULL,
                                    NULL,
                                    (LPBYTE)wbuffer.data(),
                                    &cpu_brand_size) == ERROR_SUCCESS) {
                    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wbuffer.data(), -1, NULL, 0, NULL, NULL);
                    if (size_needed > 0) {
                        description.resize(size_needed);
                        WideCharToMultiByte(CP_UTF8, 0, wbuffer.data(), -1, &description[0], size_needed, NULL, NULL);
                        if (description.find('\0') != std::string::npos) {
                            description.resize(description.find('\0'));
                        }
                    }
                }
            }
            RegCloseKey(hKey);
        }
#else
char value_name_a[256];
WideCharToMultiByte(CP_ACP, 0, L"ProcessorNameString", -1, value_name_a, sizeof(value_name_a), NULL, NULL);
RegQueryValueExW(hKey, L"ProcessorNameString", NULL, NULL, (LPBYTE)processor_name, &data_size);

char value_name_a[256];
WideCharToMultiByte(CP_ACP, 0, L"Identifier", -1, value_name_a, sizeof(value_name_a), NULL, NULL);
RegQueryValueExW(hKey, L"Identifier", NULL, NULL, (LPBYTE)processor_name, &data_size);
#endif 