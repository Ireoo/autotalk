cmake_minimum_required(VERSION 3.10)
project(AutoTalk)

# 启用CUDA支持
enable_language(CUDA)
find_package(CUDAToolkit REQUIRED)

# 设置CUDA编译选项
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_ARCHITECTURES 75 80 86 89)
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --use-local-env")
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -Xcompiler \"/EHsc\"")
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -O3")
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -D_FORCE_INLINES")

# 设置CUDA特性
set(GGML_CUDA ON CACHE BOOL "Enable CUDA support")
set(GGML_CUDA_F16 ON CACHE BOOL "Enable CUDA FP16 support")
set(GGML_CUDA_FA ON CACHE BOOL "Enable CUDA fast attention")
set(GGML_CUDA_GRAPHS ON CACHE BOOL "Enable CUDA graphs")
set(GGML_CUDA_FORCE_MMQ ON CACHE BOOL "Force MMQ for CUDA")
set(GGML_CUDA_FORCE_CUBLAS ON CACHE BOOL "Force cuBLAS for CUDA")

# 设置C++标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 设置vcpkg工具链
set(CMAKE_TOOLCHAIN_FILE "${CMAKE_CURRENT_SOURCE_DIR}/vcpkg/scripts/buildsystems/vcpkg.cmake" CACHE STRING "")

# 查找PortAudio库
# find_package(PortAudio REQUIRED)  # 注释掉这行

# 设置构建共享库
set(BUILD_SHARED_LIBS ON)

# 添加cmake模块路径
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake")

# libsndfile 配置
set(BUILD_PROGRAMS OFF CACHE BOOL "Build programs")
set(BUILD_EXAMPLES OFF CACHE BOOL "Build examples")
set(BUILD_TESTING OFF CACHE BOOL "Build tests")
set(ENABLE_EXTERNAL_LIBS OFF CACHE BOOL "Enable external libs")
set(ENABLE_MPEG OFF CACHE BOOL "Enable MPEG support")

# 添加 libsndfile 作为子项目
add_subdirectory(third_party/libsndfile)

# 设置PortAudio编译选项
option(PA_BUILD_SHARED "Build PortAudio shared library" ON)  # 修改为ON
option(PA_BUILD_STATIC "Build PortAudio static library" OFF)  # 修改为OFF
option(PA_BUILD_EXAMPLES "Build PortAudio examples" OFF)
option(PA_BUILD_TESTS "Build PortAudio tests" OFF)
option(PA_DLL_LINK_WITH_STATIC_RUNTIME "Link PortAudio DLL with static runtime libraries" OFF)
option(PA_ENABLE_DEBUG_OUTPUT "Enable debug output for PortAudio" OFF)

# 添加PortAudio作为子项目
add_subdirectory(portaudio)

# 添加whisper.cpp作为子目录
add_subdirectory(whisper.cpp)

# 包含头文件目录
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/whisper.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/portaudio/include
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libsndfile/include
)

# 添加系统监控源文件
set(MONITORING_SOURCES
    src/system_monitor.cpp
)

# 添加主程序源文件
add_executable(autotalk 
    src/main.cpp
    src/audio_capture.cpp
    ${MONITORING_SOURCES}
)

# 设置编译选项
if(MSVC)
    target_compile_options(autotalk PRIVATE /utf-8 /EHsc)
endif()

# 链接库
target_link_libraries(autotalk PRIVATE
    portaudio
    whisper
    sndfile
)

# Windows特定链接
if(WIN32)
    target_link_libraries(autotalk PRIVATE pdh)
endif()

# 复制模型目录
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/models) 