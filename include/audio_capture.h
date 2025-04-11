#pragma once

#include <vector>
#include <functional>
#include <string>
#include "portaudio.h"

class AudioCapture {
public:
    AudioCapture();
    ~AudioCapture();

    bool initialize();
    bool start(std::function<void(const std::vector<float>&)> callback);
    void stop();
    
    // 获取可用的输入设备列表
    std::vector<std::pair<int, std::string>> getInputDevices() const;
    
    // 设置输入设备
    bool setInputDevice(int deviceIndex);

private:
    static int paCallback(const void* inputBuffer, void* outputBuffer,
                         unsigned long framesPerBuffer,
                         const PaStreamCallbackTimeInfo* timeInfo,
                         PaStreamCallbackFlags statusFlags,
                         void* userData);

    PaStream* stream_;
    std::function<void(const std::vector<float>&)> callback_;
    bool initialized_;
    int currentDeviceIndex_;
    std::vector<float> audioBuffer_;  // 预分配的音频缓冲区
}; 