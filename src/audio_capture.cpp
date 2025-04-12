#include "../include/audio_capture.h"
#include <iostream>
#include <set>

AudioCapture::AudioCapture() 
    : stream_(nullptr)
    , initialized_(false)
    , currentDeviceIndex_(-1)
    , audioBuffer_(512)  // 预分配缓冲区
{
}

AudioCapture::~AudioCapture() {
    stop();
}

bool AudioCapture::initialize() {
    if (initialized_) {
        return true;
    }
    
    PaError err = Pa_Initialize();
    if (err != paNoError) {
        std::cerr << "PortAudio 初始化失败: " << Pa_GetErrorText(err) << std::endl;
        return false;
    }
    initialized_ = true;
    return true;
}

std::vector<std::pair<int, std::string>> AudioCapture::getInputDevices() const {
    std::vector<std::pair<int, std::string>> devices;
    if (!initialized_) {
        std::cerr << "AudioCapture 未初始化" << std::endl;
        return devices;
    }

    int numDevices = Pa_GetDeviceCount();
    if (numDevices < 0) {
        std::cerr << "获取设备数量失败: " << Pa_GetErrorText(numDevices) << std::endl;
        return devices;
    }

    // 用于存储已处理的设备名称
    std::vector<std::string> processedNames;

    // devices.push_back({0, "默认设备"});
    // processedNames.push_back("默认设备");
    
    for (int i = 0; i < numDevices; i++) {
        const PaDeviceInfo* deviceInfo = Pa_GetDeviceInfo(i);

        devices.push_back({i, deviceInfo->name});
        processedNames.push_back(deviceInfo->name);

        // if (deviceInfo->maxInputChannels > 0) {
        //     std::string deviceName = deviceInfo->name;
            
        //     // 检查是否是麦克风设备
        //     if (deviceName.find("麦克风") != std::string::npos || 
        //         deviceName.find("Microphone") != std::string::npos || 
        //         deviceName.find("input") != std::string::npos) {
                
        //         // 检查是否与已处理的设备名称相似
        //         bool isDuplicate = false;
        //         for (const auto& processedName : processedNames) {
        //             // 如果新设备名称包含已处理名称，或者已处理名称包含新设备名称
        //             if (deviceName.find(processedName) != std::string::npos || 
        //                 processedName.find(deviceName) != std::string::npos) {
        //                 isDuplicate = true;
        //                 break;
        //             }
        //         }
                
        //         if (!isDuplicate) {
        //             devices.push_back({i, deviceName});
        //             processedNames.push_back(deviceName);
        //         }
        //     }
        // }
    }

    return devices;
}

bool AudioCapture::setInputDevice(int deviceIndex) {
    if (!initialized_) {
        std::cerr << "AudioCapture 未初始化" << std::endl;
        return false;
    }

    int numDevices = Pa_GetDeviceCount();
    if (deviceIndex < 0 || deviceIndex >= numDevices) {
        std::cerr << "设备索引无效" << std::endl;
        return false;
    }

    const PaDeviceInfo* deviceInfo = Pa_GetDeviceInfo(deviceIndex);
    if (deviceInfo->maxInputChannels == 0) {
        std::cerr << "所选设备不是输入设备" << std::endl;
        return false;
    }

    currentDeviceIndex_ = deviceIndex;
    return true;
}

bool AudioCapture::start(std::function<void(const std::vector<float>&)> callback) {
    if (!initialized_) {
        std::cerr << "AudioCapture 未初始化" << std::endl;
        return false;
    }

    callback_ = callback;

    PaStreamParameters inputParameters;
    inputParameters.device = (currentDeviceIndex_ >= 0) ? currentDeviceIndex_ : Pa_GetDefaultInputDevice();
    if (inputParameters.device == paNoDevice) {
        std::cerr << "未找到输入设备" << std::endl;
        return false;
    }

    inputParameters.channelCount = 1;
    inputParameters.sampleFormat = paFloat32;
    inputParameters.suggestedLatency = Pa_GetDeviceInfo(inputParameters.device)->defaultLowInputLatency;
    inputParameters.hostApiSpecificStreamInfo = nullptr;

    PaError err = Pa_OpenStream(
        &stream_,
        &inputParameters,
        nullptr,
        16000,
        512,
        paClipOff,
        paCallback,
        this
    );

    if (err != paNoError) {
        std::cerr << "打开音频流失败: " << Pa_GetErrorText(err) << std::endl;
        return false;
    }

    err = Pa_StartStream(stream_);
    if (err != paNoError) {
        std::cerr << "启动音频流失败: " << Pa_GetErrorText(err) << std::endl;
        return false;
    }

    return true;
}

void AudioCapture::stop() {
    if (stream_) {
        Pa_StopStream(stream_);
        Pa_CloseStream(stream_);
        stream_ = nullptr;
    }
}

int AudioCapture::paCallback(
    const void* inputBuffer,
    void* outputBuffer,
    unsigned long framesPerBuffer,
    const PaStreamCallbackTimeInfo* timeInfo,
    PaStreamCallbackFlags statusFlags,
    void* userData
) {
    AudioCapture* self = static_cast<AudioCapture*>(userData);
    const float* in = static_cast<const float*>(inputBuffer);

    if (in != nullptr) {
        // 确保缓冲区大小足够
        if (self->audioBuffer_.size() < framesPerBuffer) {
            self->audioBuffer_.resize(framesPerBuffer);
        }
        
        // 复制数据到预分配的缓冲区
        std::copy(in, in + framesPerBuffer, self->audioBuffer_.begin());
        
        // 调用回调函数，传递包含实际数据大小的视图
        self->callback_(std::vector<float>(self->audioBuffer_.begin(), self->audioBuffer_.begin() + framesPerBuffer));
    }

    return paContinue;
} 