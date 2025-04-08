#ifdef _WIN32
        HKEY hKey;
        if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
            DWORD size = 0;
            if (RegQueryValueExW(hKey, L"ProcessorNameString", nullptr, nullptr, nullptr, &size) == ERROR_SUCCESS && size > 0) {
                std::vector<wchar_t> buf(size/sizeof(wchar_t));
                if (RegQueryValueExW(hKey, L"ProcessorNameString", nullptr, nullptr, (LPBYTE)buf.data(), &size) == ERROR_SUCCESS) {
                    // Convert wide string to UTF-8
                    int utf8_size = WideCharToMultiByte(CP_UTF8, 0, buf.data(), -1, nullptr, 0, nullptr, nullptr);
                    if (utf8_size > 0) {
                        std::vector<char> utf8_buf(utf8_size);
                        if (WideCharToMultiByte(CP_UTF8, 0, buf.data(), -1, utf8_buf.data(), utf8_size, nullptr, nullptr) > 0) {
                            ggml_cpu_info.name = utf8_buf.data();
                        }
                    }
                }
            }
            RegCloseKey(hKey);
        }
#endif