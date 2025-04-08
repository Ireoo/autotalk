#ifdef _WIN32
    // 简化的处理器信息获取
    strcpy(processor_name, "Unknown Processor");
    int cpuInfo[4] = {-1};
    __cpuid(cpuInfo, 0x80000002);
    memcpy(processor_name, cpuInfo, sizeof(cpuInfo));
    __cpuid(cpuInfo, 0x80000003);
    memcpy(processor_name + 16, cpuInfo, sizeof(cpuInfo));
    __cpuid(cpuInfo, 0x80000004);
    memcpy(processor_name + 32, cpuInfo, sizeof(cpuInfo));
#else
char value_name_a[256];
WideCharToMultiByte(CP_ACP, 0, L"ProcessorNameString", -1, value_name_a, sizeof(value_name_a), NULL, NULL);
RegQueryValueExW(hKey, L"ProcessorNameString", NULL, NULL, (LPBYTE)processor_name, &data_size);

char value_name_a[256];
WideCharToMultiByte(CP_ACP, 0, L"Identifier", -1, value_name_a, sizeof(value_name_a), NULL, NULL);
RegQueryValueExW(hKey, L"Identifier", NULL, NULL, (LPBYTE)processor_name, &data_size);
#endif 