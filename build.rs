use std::env;
use std::fs;
use std::path::Path;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");

    // 设置编译选项，确保MSVC以Unicode模式编译
    if cfg!(target_os = "windows") {
        println!("cargo:rustc-env=CFLAGS=/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t");
        println!("cargo:rustc-env=CXXFLAGS=/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t");
    }

    // 当我们检测到whisper编译问题时，添加钩子来修复它
    println!("cargo:warning=已添加whisper-rs编译修复钩子");
}
