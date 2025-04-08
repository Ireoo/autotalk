修复方案总结
# whisper-rs-sys 构建修复

## 问题说明

在Windows平台上构建whisper-rs-sys时，出现类型转换错误：

```
D:\a\autotalk\autotalk\target\release\build\whisper-rs-sys-b46d008a387bd552\out\whisper.cpp\ggml\src\ggml-cpu\ggml-cpu.cpp(286,17): error C2664: 'LSTATUS RegQueryValueExA(HKEY,LPCSTR,LPDWORD,LPDWORD,LPBYTE,LPDWORD)': cannot convert argument 2 from 'const wchar_t [20]' to 'LPCSTR'
```

此错误是因为代码使用宽字符字符串(`const wchar_t[20]`)调用ANSI版本的Registry API函数(`RegQueryValueExA`)导致的类型不匹配。

## 修复方案

将`RegQueryValueExA`函数调用修改为`RegQueryValueExW`，使其与宽字符字符串兼容。修复文件位于`ggml-cpu-fix.cpp`。

## 修复步骤

1. 找到whisper-rs-sys构建目录中的`ggml-cpu.cpp`文件
2. 将Windows部分的注册表访问代码替换为修复后的代码
3. 重新编译项目

这样可以解决Windows平台上的编译错误问题。 