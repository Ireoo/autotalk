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
constexpr int MAX_BUFFER_SIZE = SAMPLE_RATE * 30;   // 30 seconds of audio
constexpr int AUDIO_CONTEXT_SIZE = SAMPLE_RATE * 1; // 3 seconds context
constexpr int MIN_AUDIO_SAMPLES = SAMPLE_RATE;      // 至少1秒的音频数据

// Global variables
std::atomic<bool> running(true);
std::deque<float> audioBuffer;
std::mutex bufferMutex;
whisper_context *ctx = nullptr;
SystemMonitor *systemMonitor = nullptr;

// 使用无锁队列替代原有的互斥锁保护队列
const size_t AUDIO_QUEUE_SIZE = 1024; // 队列大小
boost::lockfree::spsc_queue<std::vector<float>, boost::lockfree::capacity<AUDIO_QUEUE_SIZE>> audioQueue;

// 音频处理相关的全局变量
std::vector<float> audio_chunk;
std::string confirmInfo;
const int MAX_AUDIO_LENGTH = 10 * SAMPLE_RATE; // 最大音频长度（10秒）

// Signal handler for Ctrl+C
void signalHandler(int signal)
{
    if (signal == SIGINT)
    {
        running = false;
        std::cout << "\n停止录音并退出..." << std::endl;
    }
}

// Audio data processing callback
void processAudio(const std::vector<float> &buffer)
{
    // 使用无锁队列的push方法
    while (!audioQueue.push(buffer))
    {
        // 如果队列已满，等待一小段时间
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
}

// Helper function: Convert UTF-8 string to display encoding
std::string convertToLocalEncoding(const char *utf8Text)
{
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

// 语音识别处理线程函数
void processSpeechRecognition()
{
    while (running)
    {
        if (audio_chunk.size() >= SAMPLE_RATE)
        {
            try
            {
                whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
                wparams.print_realtime = false;
                wparams.print_progress = false;
                wparams.print_timestamps = true;
                wparams.translate = false;
                wparams.language = "zh";
                wparams.n_threads = std::thread::hardware_concurrency();
                wparams.offset_ms = 0;
                wparams.duration_ms = 0;
                wparams.audio_ctx = 768;
                wparams.max_len = 0;
                wparams.token_timestamps = true;
                wparams.thold_pt = 0.01f;
                wparams.max_tokens = 32;
                wparams.temperature = 0.0f;
                wparams.temperature_inc = 0.0f;
                wparams.entropy_thold = 2.4f;
                wparams.logprob_thold = -1.0f;
                wparams.no_speech_thold = 0.6f;

                // 获取当前时间戳
                auto now = std::chrono::system_clock::now();
                auto now_time = std::chrono::system_clock::to_time_t(now);
                std::stringstream ss;
                ss << std::put_time(std::localtime(&now_time), "%Y-%m-%d-%H-%M-%S");
                auto timestamp = ss.str();

                // 复制音频数据以避免异步访问问题
                // std::vector<float> audio_copy;
                // {
                //     std::lock_guard<std::mutex> lock(bufferMutex);
                //     audio_copy = audio_chunk;
                // }

                if (whisper_full(ctx, wparams, audio_chunk.data(), audio_chunk.size()) == 0)
                {
                    const int n_segments = whisper_full_n_segments(ctx);
                    std::string recognized_text;
                    for (int i = 0; i < n_segments; ++i)
                    {
                        const char *text = whisper_full_get_segment_text(ctx, i);
                        if (text[0] != '\0')
                        {
                            recognized_text += text;
                        }
                    }

                    if (std::regex_search(recognized_text, std::regex("^(謝謝大家|謝謝觀看|謝謝觀看|謝謝收看|\\()")))
                    {
                        std::lock_guard<std::mutex> lock(bufferMutex);
                        audio_chunk.erase(audio_chunk.begin(), audio_chunk.end());
                        if (running)
                        {
                            CONSOLE_SCREEN_BUFFER_INFO csbi;
                            GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi);
                            int consoleWidth = csbi.dwSize.X;
                            std::cout << "\r" << std::string(consoleWidth, ' ') << "\r[" << timestamp << "]: 识别中..." << std::flush;
                        }
                    }
                    else
                    {
                        if (running)
                        {
                            // 获取控制台宽度，用于清除当前行
                            CONSOLE_SCREEN_BUFFER_INFO csbi;
                            GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi);
                            int consoleWidth = csbi.dwSize.X;
                            std::cout << "\r" << std::string(consoleWidth, ' ') << "\r[" << timestamp << "]: " << recognized_text << std::flush;
                        }
                    }

                    if (std::regex_search(recognized_text, std::regex("[\\.!?。！？]$")))
                    {
                        std::lock_guard<std::mutex> lock(bufferMutex);
                        audio_chunk.erase(audio_chunk.begin(), audio_chunk.end());
                        std::cout << std::endl;
                    }
                }
            }
            catch (const std::exception &e)
            {
                std::cerr << "语音识别处理错误: " << e.what() << std::endl;
            }
            catch (...)
            {
                std::cerr << "语音识别处理发生未知错误" << std::endl;
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
}

// 音频处理线程函数
void processAudioStream()
{
    while (running)
    {
        std::vector<float> currentAudio;

        if (audioQueue.pop(currentAudio))
        {
            // 计算音频能量，用于噪音检测
            float energy = 0.0f;
            for (const auto& sample : currentAudio) {
                energy += sample * sample;
            }
            energy /= currentAudio.size();
            
            // 使用自适应噪音阈值
            static float noiseThreshold = 0.000001f; // 初始噪音阈值
            static float avgEnergy = energy;      // 初始平均能量
            static const float adaptRate = 0.000001f; // 自适应调整率
            
            // 更新平均能量（使用指数移动平均）
            avgEnergy = avgEnergy * (1 - adaptRate) + energy * adaptRate;
            
            // 动态调整噪音阈值（设为平均能量的一定比例）
            noiseThreshold = avgEnergy * 0.000001f;
            
            // 只有当能量超过噪音阈值时才处理音频
            if (energy > noiseThreshold) {
                std::lock_guard<std::mutex> lock(bufferMutex);
                audio_chunk.insert(audio_chunk.end(), currentAudio.begin(), currentAudio.end());
            }

            // size_t keep_size = SAMPLE_RATE * 10; // 保留5秒的数据
            // if (audio_chunk.size() > keep_size)
            // {
            //     audio_chunk.erase(audio_chunk.begin(), audio_chunk.end() - keep_size);
            // }
        }
        // else
        // {
        //     std::this_thread::sleep_for(std::chrono::milliseconds(1));
        // }
    }
}

int main(int argc, char **argv)
{
    // 设置信号处理
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);

    // 解析命令行参数
    int selectedMic = 0; // 初始值设为-1，表示未指定
    std::string modelPath = "models/ggml-medium-zh.bin";
    bool listDevices = false;

    for (int i = 1; i < argc; i++)
    {
        std::string arg = argv[i];
        if (arg == "--mic" && i + 1 < argc)
        {
            selectedMic = std::stoi(argv[++i]);
        }
        else if (arg == "--model" && i + 1 < argc)
        {
            modelPath = argv[++i];
        }
        else if (arg == "--list")
        {
            listDevices = true;
        }
    }

// 设置中文控制台输出
#ifdef _WIN32
    SetConsoleOutputCP(CP_UTF8);
#endif

    // 初始化音频捕获
    AudioCapture audioCapture;
    if (!audioCapture.initialize())
    {
        std::cerr << "无法初始化音频捕获" << std::endl;
        return 1;
    }

    // 获取并显示可用的输入设备
    auto devices = audioCapture.getInputDevices();
    std::cout << "\n可用的输入设备：" << std::endl;
    for (const auto &device : devices)
    {
        std::cout << device.first << ": " << device.second << std::endl;
    }

    // 如果指定了 --list 参数，显示设备列表后退出
    if (listDevices)
    {
        return 0;
    }

    // 如果没有指定麦克风，使用列表中的第一个设备
    if (selectedMic == -1)
    {
        if (!devices.empty())
        {
            selectedMic = devices[0].first;
            std::cout << "\n使用默认输入设备：" << selectedMic << " (" << devices[0].second << ")" << std::endl;
        }
        else
        {
            std::cerr << "未找到可用的输入设备" << std::endl;
            return 1;
        }
    }
    else
    {
        std::cout << "\n使用指定的输入设备：" << selectedMic << std::endl;
    }

    std::cout << "正在初始化语音识别系统..." << std::endl;

    // 初始化 whisper 模型
    ctx = whisper_init_from_file(modelPath.c_str());
    if (!ctx)
    {
        std::cerr << "无法加载模型，请确保模型文件 " << modelPath << " 存在" << std::endl;
        return 1;
    }

    // 初始化系统监控
    systemMonitor = new SystemMonitor();
    systemMonitor->start();

    if (!audioCapture.setInputDevice(selectedMic))
    {
        std::cerr << "无法设置输入设备" << std::endl;
        whisper_free(ctx);
        delete systemMonitor;
        return 1;
    }

    // 启动音频处理线程
    std::thread processThread(processAudioStream);
    std::thread recognitionThread(processSpeechRecognition);

    // 启动音频捕获
    if (!audioCapture.start([](const std::vector<float> &buffer)
                            { processAudio(buffer); }))
    {
        std::cerr << "无法启动音频捕获" << std::endl;
        running = false;
        processThread.join();
        recognitionThread.join();
        whisper_free(ctx);
        delete systemMonitor;
        return 1;
    }

    std::cout << "\n系统已启动，正在进行实时语音识别..." << std::endl;
    std::cout << "按 Ctrl+C 停止程序" << std::endl;

    // 等待所有线程结束
    processThread.join();
    recognitionThread.join();

    // 清理资源
    audioCapture.stop();
    whisper_free(ctx);
    delete systemMonitor;

    std::cout << "\n程序已停止" << std::endl;
    return 0;
}