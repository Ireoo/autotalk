#include <iostream>
#include <vector>
#include <deque>
#include <string>
#include <thread>
#include <mutex>
#include <atomic>
#include <signal.h>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <locale>
#include <codecvt>
#include <queue>
#include <limits>
#include <iomanip>
#include <regex>
#include <sstream>
#include <boost/lockfree/spsc_queue.hpp>
#include "../third_party/libsndfile/include/sndfile.h"
#ifdef _WIN32
#include <Windows.h>
#include <fcntl.h>
#include <io.h>
#endif
#include "portaudio.h"
#include <future>
#include <condition_variable>

#include "../include/audio_capture.h"
#include "../include/system_monitor.h"
#include "../whisper.cpp/include/whisper.h"

// Constants
constexpr int SAMPLE_RATE = 16000;
constexpr int FRAME_SIZE = 512;
constexpr int MAX_BUFFER_SIZE = SAMPLE_RATE * 30; // 30 seconds of audio
constexpr int AUDIO_CONTEXT_SIZE = SAMPLE_RATE * 3; // 3 seconds context
constexpr int MIN_AUDIO_SAMPLES = SAMPLE_RATE; // 至少1秒的音频数据

// Global variables
std::atomic<bool> running(true);
std::deque<float> audioBuffer;
std::mutex bufferMutex;
whisper_context* ctx = nullptr;
SystemMonitor* systemMonitor = nullptr;

// 使用无锁队列替代原有的互斥锁保护队列
const size_t AUDIO_QUEUE_SIZE = 1024;  // 队列大小
boost::lockfree::spsc_queue<std::vector<float>, boost::lockfree::capacity<AUDIO_QUEUE_SIZE>> audioQueue;

// 音频处理相关的全局变量
std::vector<float> audio_chunk;
std::string confirmInfo;
const int MAX_AUDIO_LENGTH = 10 * SAMPLE_RATE; // 最大音频长度（10秒）

// Signal handler for Ctrl+C
void signalHandler(int signal) {
    if (signal == SIGINT) {
        running = false;
        std::cout << "\n停止录音并退出..." << std::endl;
    }
}

// Audio data processing callback
void processAudio(const std::vector<float>& buffer) {
    // 使用无锁队列的push方法
    while (!audioQueue.push(buffer)) {
        // 如果队列已满，等待一小段时间
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
}

// Helper function: Convert UTF-8 string to display encoding
std::string convertToLocalEncoding(const char* utf8Text) {
#ifdef _WIN32
    // 在Windows上使用UTF-8到本地编码的转换
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8Text, -1, nullptr, 0);
    std::vector<wchar_t> wstr(len);
    MultiByteToWideChar(CP_UTF8, 0, utf8Text, -1, wstr.data(), len);
    
    len = WideCharToMultiByte(CP_ACP, 0, wstr.data(), -1, nullptr, 0, nullptr, nullptr);
    std::vector<char> str(len);
    WideCharToMultiByte(CP_ACP, 0, wstr.data(), -1, str.data(), len, nullptr, nullptr);
    
    return std::string(str.data());
#else
    // 在Linux上直接返回UTF-8
    return std::string(utf8Text);
#endif
}

// 音频处理线程函数
void processAudioStream() {
    while (running) {
        std::vector<float> currentAudio;
        
        // 使用无锁队列的pop方法
        if (audioQueue.pop(currentAudio)) {
            // 将新的音频数据添加到 audio_chunk
            audio_chunk.insert(audio_chunk.end(), currentAudio.begin(), currentAudio.end());

            // 如果 audio_chunk 长度超过阈值，则进行处理
            if (audio_chunk.size() >= SAMPLE_RATE) {
                // 限制音频长度
                if (audio_chunk.size() > MAX_AUDIO_LENGTH) {
                    audio_chunk.erase(audio_chunk.begin(), audio_chunk.end() - MAX_AUDIO_LENGTH);
                }

                // 获取当前时间戳
                auto now = std::chrono::system_clock::now();
                auto now_time = std::chrono::system_clock::to_time_t(now);
                std::stringstream ss;
                ss << std::put_time(std::localtime(&now_time), "%Y-%m-%d-%H-%M-%S");
                auto timestamp = ss.str();

                // 保存音频文件
                std::string filename = "./voice/" + timestamp + ".wav";
                std::filesystem::create_directories("./voice");
                
                // 使用 libsndfile 写入 WAV 文件
                SF_INFO sfInfo;
                sfInfo.samplerate = SAMPLE_RATE;
                sfInfo.channels = 1;
                sfInfo.format = SF_FORMAT_WAV | SF_FORMAT_FLOAT;
                
                SNDFILE* sndFile = sf_open(filename.c_str(), SFM_WRITE, &sfInfo);
                if (sndFile) {
                    sf_write_float(sndFile, audio_chunk.data(), audio_chunk.size());
                    sf_close(sndFile);
                }

                // 运行语音识别
                whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
                wparams.print_realtime = false;
                wparams.print_progress = false;
                wparams.print_timestamps = true;
                wparams.translate = false;
                wparams.language = "zh";
                wparams.n_threads = 4;
                wparams.offset_ms = 0;
                wparams.duration_ms = 0;
                wparams.audio_ctx = 768;
                wparams.max_len = 0;
                wparams.token_timestamps = true;
                wparams.thold_pt = 0.01f;
                wparams.max_tokens = 32;

                if (whisper_full(ctx, wparams, audio_chunk.data(), audio_chunk.size()) == 0) {
                    const int n_segments = whisper_full_n_segments(ctx);
                    std::string recognized_text;
                    for (int i = 0; i < n_segments; ++i) {
                        const char* text = whisper_full_get_segment_text(ctx, i);
                        if (text[0] != '\0') {
                            recognized_text += text;
                        }
                    }

                    // 输出识别结果
                    std::cout << "[" << timestamp << "]: " << recognized_text << std::endl;

                    // 检查是否需要确认
                    if (!confirmInfo.empty()) {
                        std::cout << "Verify content: " << confirmInfo << std::endl;
                        if (std::regex_search(recognized_text, std::regex("(yes|ok|sure|是|好)", std::regex::icase))) {
                            confirmInfo.clear();
                            audio_chunk.clear();
                            std::cout << "Confirmed. Master, What can I do for you?" << std::endl;
                        } else if (std::regex_search(recognized_text, std::regex("(no|cancel|不要|取消)", std::regex::icase))) {
                            confirmInfo.clear();
                            audio_chunk.clear();
                            std::cout << "Canceled. Master, What can I do for you?" << std::endl;
                        }
                    } else {
                        // 检查是否以句号结尾
                        if (std::regex_search(recognized_text, std::regex("[^.!?]{1,}[.!?]$|^$"))) {
                            audio_chunk.clear();
                            if (!recognized_text.empty() && recognized_text != "Thank you." && recognized_text != "you") {
                                std::cout << "[>>>>]: '" << recognized_text << "'" << std::endl;
                                // TODO: 在这里添加 ChatGPT 处理逻辑
                            }
                        }
                    }
                }

                // 清理临时文件
                // std::filesystem::remove(filename);
            }
        } else {
            // 如果队列为空，等待一小段时间
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    }
}

int main(int argc, char** argv) {
    // 设置信号处理
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);

    // 设置中文控制台输出
    #ifdef _WIN32
    SetConsoleOutputCP(CP_UTF8);
    #endif

    std::cout << "正在初始化语音识别系统..." << std::endl;

    // 初始化 whisper 模型
    ctx = whisper_init_from_file("models/ggml-medium-zh.bin");
    if (!ctx) {
        std::cerr << "无法加载模型，请确保 models/ggml-medium-zh.bin 文件存在" << std::endl;
        return 1;
    }

    // 初始化系统监控
    systemMonitor = new SystemMonitor();
    systemMonitor->start();

    // 初始化音频捕获
    AudioCapture audioCapture;
    if (!audioCapture.initialize()) {
        std::cerr << "无法初始化音频捕获" << std::endl;
        whisper_free(ctx);
        delete systemMonitor;
        return 1;
    }

    // 获取并显示可用的输入设备
    auto devices = audioCapture.getInputDevices();
    std::cout << "\n可用的输入设备：" << std::endl;
    for (const auto& device : devices) {
        std::cout << device.first << ": " << device.second << std::endl;
    }

    // 选择默认设备或让用户选择
    std::cout << "\n请选择输入设备编号（输入对应数字）：";
    int deviceIndex;
    std::cin >> deviceIndex;

    if (!audioCapture.setInputDevice(deviceIndex)) {
        std::cerr << "无法设置输入设备" << std::endl;
        whisper_free(ctx);
        delete systemMonitor;
        return 1;
    }

    // 启动音频处理线程
    std::thread processThread(processAudioStream);

    // 启动音频捕获
    if (!audioCapture.start([](const std::vector<float>& buffer) {
        processAudio(buffer);
    })) {
        std::cerr << "无法启动音频捕获" << std::endl;
        running = false;
        processThread.join();
        whisper_free(ctx);
        delete systemMonitor;
        return 1;
    }

    std::cout << "\n系统已启动，正在进行实时语音识别..." << std::endl;
    std::cout << "按 Ctrl+C 停止程序" << std::endl;

    // 等待音频处理线程结束
    processThread.join();

    // 清理资源
    audioCapture.stop();
    whisper_free(ctx);
    delete systemMonitor;

    std::cout << "\n程序已停止" << std::endl;
    return 0;
} 