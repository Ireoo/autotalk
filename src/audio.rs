use anyhow::{Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Device, Host, SampleFormat, Stream};
use log::{debug, error, info, warn};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};

pub struct AudioCapture {
    host: Host,
    device: Option<Device>,
    stream: Option<Stream>,
    sample_rate: u32,
    channels: u16,
    buffer: Arc<Mutex<Vec<f32>>>,
    tx: Option<mpsc::Sender<Vec<f32>>>,
}

impl AudioCapture {
    pub fn new() -> Result<Self> {
        info!("初始化音频捕获系统");
        let host = match cpal::default_host() {
            host => {
                info!("成功获取默认音频主机: {}", host.id().name());
                host
            }
        };

        // 检查主机是否支持输入设备
        let default_input = host.default_input_device();
        if default_input.is_none() {
            warn!("检测不到默认音频输入设备");
        } else {
            info!("检测到默认音频输入设备");
        }

        Ok(Self {
            host,
            device: None,
            stream: None,
            sample_rate: 48000, // 使用48kHz采样率，匹配大多数设备
            channels: 2,        // 支持立体声
            buffer: Arc::new(Mutex::new(Vec::new())),
            tx: None,
        })
    }

    pub fn list_devices(&self) -> Result<Vec<String>> {
        info!("正在获取可用输入设备列表");

        // 获取所有设备
        let all_devices = self.host.devices().context("无法获取音频设备列表")?;

        // 只筛选输入设备
        let mut input_devices = Vec::new();
        let mut device_names = Vec::new();

        for device in all_devices {
            // 检查设备是否支持输入
            match device.supported_input_configs() {
                Ok(configs) => {
                    if configs.count() > 0 {
                        // 这是一个有效的输入设备
                        if let Ok(name) = device.name() {
                            input_devices.push(device);
                            device_names.push(name);
                        }
                    }
                }
                Err(_) => {
                    // 不是输入设备，跳过
                    continue;
                }
            }
        }

        if device_names.is_empty() {
            warn!("未发现可用麦克风输入设备");
        } else {
            info!("发现 {} 个麦克风输入设备", device_names.len());
            for (i, name) in device_names.iter().enumerate() {
                debug!("麦克风 {}: {}", i, name);
            }
        }

        Ok(device_names)
    }

    pub fn select_device(&mut self, device_name: Option<String>) -> Result<()> {
        let input_devices = self.get_input_devices()?;

        self.device = match device_name {
            Some(name) => {
                info!("尝试使用指定麦克风: {}", name);
                // 在输入设备中查找名称匹配的设备
                let device = input_devices
                    .iter()
                    .find(|device| {
                        device
                            .name()
                            .map(|device_name| device_name == name)
                            .unwrap_or(false)
                    })
                    .cloned();

                if device.is_none() {
                    warn!("未找到指定麦克风: {}, 将尝试使用默认输入设备", name);
                    Some(
                        self.host
                            .default_input_device()
                            .context("未找到默认输入设备")?,
                    )
                } else {
                    info!("成功找到指定麦克风: {}", name);
                    device
                }
            }
            None => {
                info!("使用默认输入设备");
                Some(
                    self.host
                        .default_input_device()
                        .context("未找到默认输入设备")?,
                )
            }
        };

        match self.device.as_ref().unwrap().name() {
            Ok(device_name) => {
                info!("已选择麦克风设备: {}", device_name);
            }
            Err(e) => {
                warn!("无法获取所选设备名称: {}", e);
            }
        }

        Ok(())
    }

    // 辅助方法，获取所有输入设备
    fn get_input_devices(&self) -> Result<Vec<Device>> {
        // 获取所有设备
        let all_devices = self.host.devices().context("无法获取音频设备列表")?;

        // 只筛选输入设备
        let mut input_devices = Vec::new();

        for device in all_devices {
            // 检查设备是否支持输入
            match device.supported_input_configs() {
                Ok(configs) => {
                    if configs.count() > 0 {
                        // 这是一个有效的输入设备
                        input_devices.push(device);
                    }
                }
                Err(_) => {
                    // 不是输入设备，跳过
                    continue;
                }
            }
        }

        Ok(input_devices)
    }

    pub fn start_capture(&mut self, tx: mpsc::Sender<Vec<f32>>) -> Result<()> {
        info!("开始启动音频捕获流程");
        self.tx = Some(tx);
        let device = self.device.as_ref().context("未选择音频设备")?;

        // 获取设备支持的配置
        info!("查询设备支持的配置");
        let supported_configs = device.supported_input_configs()?;

        // 转换为Vec以便调试和处理
        let config_vec: Vec<_> = supported_configs.collect();
        if config_vec.is_empty() {
            return Err(anyhow::anyhow!("设备不支持任何输入配置"));
        }

        debug!("设备支持 {} 种配置:", config_vec.len());
        for (i, cfg) in config_vec.iter().enumerate() {
            debug!(
                "配置 {}: 通道数: {}, 采样率: {} - {} Hz, 格式: {:?}",
                i,
                cfg.channels(),
                cfg.min_sample_rate().0,
                cfg.max_sample_rate().0,
                cfg.sample_format()
            );
        }

        // 尝试不同的配置优先级
        // 首先尝试使用我们预设的通道数和采样率
        let mut selected_config = config_vec
            .iter()
            .find(|config| {
                config.channels() == self.channels
                    && config.min_sample_rate().0 <= self.sample_rate
                    && config.max_sample_rate().0 >= self.sample_rate
            })
            .cloned();

        // 如果未找到完全匹配的配置，尝试只匹配通道数，采用最接近的采样率
        if selected_config.is_none() {
            info!("未找到完全匹配的配置，尝试寻找兼容配置");
            selected_config = config_vec
                .iter()
                .filter(|config| config.channels() == self.channels)
                .min_by_key(|config| {
                    let min_diff =
                        (config.min_sample_rate().0 as i32 - self.sample_rate as i32).abs();
                    let max_diff =
                        (config.max_sample_rate().0 as i32 - self.sample_rate as i32).abs();
                    std::cmp::min(min_diff, max_diff)
                })
                .cloned();
        }

        // 如果仍然未找到，尝试任何单通道配置
        if selected_config.is_none() {
            info!("未找到匹配通道数的配置，尝试单通道配置");
            selected_config = config_vec
                .iter()
                .filter(|config| config.channels() == 1)
                .max_by_key(|config| config.max_sample_rate().0)
                .cloned();
        }

        // 如果仍然未找到，使用任何可用配置
        if selected_config.is_none() {
            info!("尝试使用任何可用配置");
            selected_config = config_vec.first().cloned();
        }

        // 处理最终选择的配置
        let config = match selected_config {
            Some(config) => {
                // 确定要使用的采样率
                let sample_rate = if config.min_sample_rate().0 <= self.sample_rate
                    && config.max_sample_rate().0 >= self.sample_rate
                {
                    self.sample_rate
                } else if self.sample_rate < config.min_sample_rate().0 {
                    config.min_sample_rate().0
                } else {
                    config.max_sample_rate().0
                };

                config.with_sample_rate(cpal::SampleRate(sample_rate))
            }
            None => {
                return Err(anyhow::anyhow!(
                    "无法为该设备找到兼容的音频配置，请尝试其他麦克风设备"
                ));
            }
        };

        // 更新内部状态以匹配实际使用的配置
        self.sample_rate = config.sample_rate().0;
        self.channels = config.channels();

        info!(
            "已选择音频配置: {}Hz, {} 通道, 格式: {:?}",
            config.sample_rate().0,
            config.channels(),
            config.sample_format()
        );

        let err_fn = |err| error!("音频流错误: {}", err);
        let buffer = Arc::clone(&self.buffer);
        let sender = self.tx.clone().unwrap();
        let channels = config.channels() as usize;

        // 创建音频处理回调
        info!("创建音频处理流");
        let stream = match config.sample_format() {
            SampleFormat::F32 => {
                info!("使用F32采样格式");
                device.build_input_stream(
                    &config.into(),
                    move |data: &[f32], _: &_| {
                        Self::process_audio_data(data, Arc::clone(&buffer), &sender, channels);
                    },
                    err_fn,
                    None,
                )
            }
            SampleFormat::I16 => {
                info!("使用I16采样格式");
                device.build_input_stream(
                    &config.into(),
                    move |data: &[i16], _: &_| {
                        let float_data: Vec<f32> =
                            data.iter().map(|&s| s as f32 / 32768.0).collect();
                        Self::process_audio_data(
                            &float_data,
                            Arc::clone(&buffer),
                            &sender,
                            channels,
                        );
                    },
                    err_fn,
                    None,
                )
            }
            SampleFormat::U16 => {
                info!("使用U16采样格式");
                device.build_input_stream(
                    &config.into(),
                    move |data: &[u16], _: &_| {
                        let float_data: Vec<f32> =
                            data.iter().map(|&s| ((s as f32) / 32768.0) - 1.0).collect();
                        Self::process_audio_data(
                            &float_data,
                            Arc::clone(&buffer),
                            &sender,
                            channels,
                        );
                    },
                    err_fn,
                    None,
                )
            }
            SampleFormat::U8 => {
                info!("使用U8采样格式");
                device.build_input_stream(
                    &config.into(),
                    move |data: &[u8], _: &_| {
                        let float_data: Vec<f32> =
                            data.iter().map(|&s| ((s as f32) / 128.0) - 1.0).collect();
                        Self::process_audio_data(
                            &float_data,
                            Arc::clone(&buffer),
                            &sender,
                            channels,
                        );
                    },
                    err_fn,
                    None,
                )
            }
            fmt => {
                let err = format!("不支持的采样格式: {:?}，请尝试其他麦克风设备", fmt);
                error!("{}", err);
                return Err(anyhow::anyhow!(err));
            }
        }
        .map_err(|e| {
            let err_msg = format!("创建音频流失败: {}，可能是设备被占用或配置不兼容", e);
            error!("{}", err_msg);
            anyhow::anyhow!(err_msg)
        })?;

        info!("音频流创建成功，启动播放");
        stream.play().map_err(|e| {
            let err_msg = format!("启动音频流失败: {}", e);
            error!("{}", err_msg);
            anyhow::anyhow!(err_msg)
        })?;

        self.stream = Some(stream);
        info!("开始捕获音频");

        Ok(())
    }

    fn process_audio_data(
        input: &[f32],
        buffer: Arc<Mutex<Vec<f32>>>,
        sender: &mpsc::Sender<Vec<f32>>,
        channels: usize,
    ) {
        // 累积音频数据
        let mut buffer = buffer.lock().unwrap();
        buffer.extend_from_slice(input);

        // 设置一个灵活的块大小，适应不同的采样率和通道数
        // 每次发送约1秒的音频
        let samples_per_second = 16000; // 我们希望输出的采样率
        let chunk_size = samples_per_second * channels;

        if buffer.len() >= chunk_size {
            // 获取音频数据块
            let audio_chunk: Vec<f32> = buffer.drain(0..chunk_size).collect();

            // 转换为单声道数据用于语音识别
            let mono_chunk: Vec<f32> = if channels > 1 {
                let mono_size = chunk_size / channels;
                let mut mono = Vec::with_capacity(mono_size);

                for i in 0..mono_size {
                    // 从多通道中平均所有声道
                    let mut sample_sum = 0.0;
                    for ch in 0..channels {
                        sample_sum += audio_chunk[i * channels + ch];
                    }
                    mono.push(sample_sum / channels as f32);
                }
                mono
            } else {
                // 已经是单声道
                audio_chunk
            };

            if let Err(e) = sender.send(mono_chunk) {
                error!("发送音频数据失败: {}", e);
            }
        }
    }

    pub fn stop_capture(&mut self) {
        if let Some(stream) = self.stream.take() {
            drop(stream);
            info!("已停止音频捕获");
        }
    }
}

impl Drop for AudioCapture {
    fn drop(&mut self) {
        self.stop_capture();
    }
}
