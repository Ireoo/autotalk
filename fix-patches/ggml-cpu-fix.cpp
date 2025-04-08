#ifdef _WIN32
        HKEY hKey;
        if (RegOpenKeyEx(HKEY_LOCAL_MACHINE,
                        TEXT("HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0"),
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
#endif 