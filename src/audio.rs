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
    pub playback_enabled: bool,
    output_device: Option<Device>,
    output_stream: Option<Stream>,
    playback_buffer: Arc<Mutex<Vec<f32>>>,
}

impl AudioCapture {
    pub fn new() -> Result<Self> {
        info!("初始化音频捕获系统");
        let host = cpal::default_host();
        let host = {
            info!("成功获取默认音频主机: {}", host.id().name());
            host
        };

        // 检查主机是否支持输入设备
        let default_input = host.default_input_device();
        if default_input.is_none() {
            warn!("检测不到默认音频输入设备");
        } else {
            info!("检测到默认音频输入设备");
        }

        // 检查主机是否支持输出设备
        let default_output = host.default_output_device();
        if default_output.is_none() {
            warn!("检测不到默认音频输出设备");
        } else {
            info!("检测到默认音频输出设备");
        }

        Ok(Self {
            host,
            device: None,
            stream: None,
            sample_rate: 16000, // 使用16kHz采样率，直接匹配识别所需
            channels: 1,       // 默认使用单声道，减少转换开销
            buffer: Arc::new(Mutex::new(Vec::with_capacity(16000))), // 预分配缓冲区
            tx: None,
            playback_enabled: false,
            output_device: None,
            output_stream: None,
            playback_buffer: Arc::new(Mutex::new(Vec::with_capacity(48000))), // 输出缓冲区
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

        // 初始化输出设备（用于音频回放）
        self.output_device = self.host.default_output_device();
        if self.output_device.is_none() {
            warn!("未找到默认音频输出设备，实时播放功能将不可用");
        } else {
            match self.output_device.as_ref().unwrap().name() {
                Ok(device_name) => {
                    info!("已选择音频输出设备: {}", device_name);
                }
                Err(e) => {
                    warn!("无法获取所选输出设备名称: {}", e);
                }
            }
        }

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

    // 新增方法：在对输入音频流进行初始化前先设置输出设备
    fn prepare_output_device(&mut self) -> Result<()> {
        if self.playback_enabled && self.output_stream.is_none() {
            // 检查输出设备是否可用
            if self.output_device.is_none() {
                self.output_device = self.host.default_output_device();
                if self.output_device.is_none() {
                    warn!("未找到默认音频输出设备，实时播放功能将不可用");
                    return Ok(());
                } else {
                    match self.output_device.as_ref().unwrap().name() {
                        Ok(device_name) => {
                            info!("已选择音频输出设备: {}", device_name);
                        }
                        Err(e) => {
                            warn!("无法获取所选输出设备名称: {}", e);
                        }
                    }
                }
            }
            
            // 创建输出流
            self.setup_output_stream(self.sample_rate, self.channels)?;
        }
        Ok(())
    }

    pub fn start_capture(&mut self, tx: mpsc::Sender<Vec<f32>>) -> Result<()> {
        info!("开始启动音频捕获流程");
        self.tx = Some(tx);
        
        // 首先完成所有输出设备设置，避免后续借用冲突
        self.prepare_output_device()?;
        
        // 提前获取所需要用到的设备，这样后面就不需要再借用self
        let input_device = self.device.as_ref().context("未选择音频设备")?;
        
        // 获取设备支持的配置
        info!("查询设备支持的配置");
        let supported_configs = input_device.supported_input_configs()?;

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
        let current_sample_rate = config.sample_rate().0;
        let current_channels = config.channels();
        
        // 捕获当前实例中需要的变量，以避免后续借用self
        let err_fn = |err| error!("音频流错误: {}", err);
        let buffer = Arc::clone(&self.buffer);
        let sender = self.tx.clone().unwrap();
        let channels = current_channels as usize;
        let playback_enabled = self.playback_enabled;
        let playback_buffer = Arc::clone(&self.playback_buffer);
        
        // 更新实例状态（注意：这里必须在创建Stream前更新sample_rate和channels）
        self.sample_rate = current_sample_rate;
        self.channels = current_channels;

        info!(
            "已选择音频配置: {}Hz, {} 通道, 格式: {:?}",
            current_sample_rate,
            current_channels,
            config.sample_format()
        );

        // 创建音频处理回调
        info!("创建音频处理流");
        let stream = match config.sample_format() {
            SampleFormat::F32 => {
                info!("使用F32采样格式");
                input_device.build_input_stream(
                    &config.into(),
                    move |data: &[f32], _: &_| {
                        Self::process_audio_data(data, Arc::clone(&buffer), &sender, channels, playback_enabled, Arc::clone(&playback_buffer));
                    },
                    err_fn,
                    None,
                )
            }
            SampleFormat::I16 => {
                info!("使用I16采样格式");
                input_device.build_input_stream(
                    &config.into(),
                    move |data: &[i16], _: &_| {
                        let float_data: Vec<f32> =
                            data.iter().map(|&s| s as f32 / 32768.0).collect();
                        Self::process_audio_data(&float_data, Arc::clone(&buffer), &sender, channels, playback_enabled, Arc::clone(&playback_buffer));
                    },
                    err_fn,
                    None,
                )
            }
            SampleFormat::U16 => {
                info!("使用U16采样格式");
                input_device.build_input_stream(
                    &config.into(),
                    move |data: &[u16], _: &_| {
                        let float_data: Vec<f32> =
                            data.iter().map(|&s| ((s as f32) / 32768.0) - 1.0).collect();
                        Self::process_audio_data(&float_data, Arc::clone(&buffer), &sender, channels, playback_enabled, Arc::clone(&playback_buffer));
                    },
                    err_fn,
                    None,
                )
            }
            SampleFormat::U8 => {
                info!("使用U8采样格式");
                input_device.build_input_stream(
                    &config.into(),
                    move |data: &[u8], _: &_| {
                        let float_data: Vec<f32> =
                            data.iter().map(|&s| ((s as f32) / 128.0) - 1.0).collect();
                        Self::process_audio_data(&float_data, Arc::clone(&buffer), &sender, channels, playback_enabled, Arc::clone(&playback_buffer));
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

    // 设置音频输出流
    fn setup_output_stream(&mut self, sample_rate: u32, channels: u16) -> Result<()> {
        if self.output_device.is_none() {
            warn!("未找到输出设备，无法设置音频回放");
            return Ok(());
        }

        let output_device = self.output_device.as_ref().unwrap();
        info!("设置音频输出流");

        // 获取支持的输出配置
        let supported_configs = output_device.supported_output_configs()?;
        let config_vec: Vec<_> = supported_configs.collect();

        if config_vec.is_empty() {
            warn!("输出设备不支持任何输出配置，无法设置音频回放");
            return Ok(());
        }

        // 尝试找到匹配采样率和通道数的配置
        let mut selected_config = config_vec
            .iter()
            .find(|config| {
                config.channels() == channels
                    && config.min_sample_rate().0 <= sample_rate
                    && config.max_sample_rate().0 >= sample_rate
            })
            .cloned();

        // 如果未找到，尝试任何支持的配置
        if selected_config.is_none() {
            selected_config = config_vec.first().cloned();
        }

        let config = match selected_config {
            Some(config) => {
                let sample_rate = if config.min_sample_rate().0 <= sample_rate
                    && config.max_sample_rate().0 >= sample_rate
                {
                    sample_rate
                } else if sample_rate < config.min_sample_rate().0 {
                    config.min_sample_rate().0
                } else {
                    config.max_sample_rate().0
                };
                config.with_sample_rate(cpal::SampleRate(sample_rate))
            }
            None => {
                warn!("未找到支持的输出配置，无法设置音频回放");
                return Ok(());
            }
        };

        info!(
            "已选择输出音频配置: {}Hz, {} 通道, 格式: {:?}",
            config.sample_rate().0,
            config.channels(),
            config.sample_format()
        );

        let err_fn = |err| error!("输出音频流错误: {}", err);
        let playback_buffer = Arc::clone(&self.playback_buffer);

        // 创建输出流
        let output_stream = match config.sample_format() {
            SampleFormat::F32 => {
                output_device.build_output_stream(
                    &config.into(),
                    move |data: &mut [f32], _: &_| {
                        // 播放缓冲区中的数据
                        let mut buffer = playback_buffer.lock().unwrap();
                        if !buffer.is_empty() {
                            let len = std::cmp::min(data.len(), buffer.len());
                            data[..len].copy_from_slice(&buffer[..len]);
                            buffer.drain(0..len);
                        } else {
                            // 如果没有数据，则静音
                            for sample in data.iter_mut() {
                                *sample = 0.0;
                            }
                        }
                    },
                    err_fn,
                    None,
                )
            }
            SampleFormat::I16 => {
                output_device.build_output_stream(
                    &config.into(),
                    move |data: &mut [i16], _: &_| {
                        // 播放缓冲区中的数据
                        let mut buffer = playback_buffer.lock().unwrap();
                        if !buffer.is_empty() {
                            let len = std::cmp::min(data.len(), buffer.len());
                            for i in 0..len {
                                // 转换浮点数为i16
                                data[i] = (buffer[i] * 32767.0) as i16;
                            }
                            buffer.drain(0..len);
                        } else {
                            // 如果没有数据，则静音
                            for sample in data.iter_mut() {
                                *sample = 0;
                            }
                        }
                    },
                    err_fn,
                    None,
                )
            }
            SampleFormat::U16 => {
                output_device.build_output_stream(
                    &config.into(),
                    move |data: &mut [u16], _: &_| {
                        // 播放缓冲区中的数据
                        let mut buffer = playback_buffer.lock().unwrap();
                        if !buffer.is_empty() {
                            let len = std::cmp::min(data.len(), buffer.len());
                            for i in 0..len {
                                // 转换浮点数为u16
                                data[i] = ((buffer[i] + 1.0) * 32767.5) as u16;
                            }
                            buffer.drain(0..len);
                        } else {
                            // 如果没有数据，则静音
                            for sample in data.iter_mut() {
                                *sample = 32768; // 中间值，表示静音
                            }
                        }
                    },
                    err_fn,
                    None,
                )
            }
            SampleFormat::U8 => {
                output_device.build_output_stream(
                    &config.into(),
                    move |data: &mut [u8], _: &_| {
                        // 播放缓冲区中的数据
                        let mut buffer = playback_buffer.lock().unwrap();
                        if !buffer.is_empty() {
                            let len = std::cmp::min(data.len(), buffer.len());
                            for i in 0..len {
                                // 转换浮点数为u8
                                data[i] = ((buffer[i] + 1.0) * 127.5) as u8;
                            }
                            buffer.drain(0..len);
                        } else {
                            // 如果没有数据，则静音
                            for sample in data.iter_mut() {
                                *sample = 128; // 中间值，表示静音
                            }
                        }
                    },
                    err_fn,
                    None,
                )
            }
            fmt => {
                warn!("不支持的输出采样格式: {:?}，无法设置音频回放", fmt);
                return Ok(());
            }
        }
        .map_err(|e| {
            let err_msg = format!("创建输出音频流失败: {}", e);
            error!("{}", err_msg);
            anyhow::anyhow!(err_msg)
        })?;

        info!("输出音频流创建成功，启动播放");
        output_stream.play().map_err(|e| {
            let err_msg = format!("启动输出音频流失败: {}", e);
            error!("{}", err_msg);
            anyhow::anyhow!(err_msg)
        })?;

        self.output_stream = Some(output_stream);
        info!("实时播放功能已启动");

        Ok(())
    }

    fn process_audio_data(
        input: &[f32],
        buffer: Arc<Mutex<Vec<f32>>>,
        sender: &mpsc::Sender<Vec<f32>>,
        channels: usize,
        playback_enabled: bool,
        playback_buffer: Arc<Mutex<Vec<f32>>>,
    ) {
        // 直接使用输入数据进行播放，减少不必要的缓冲
        if playback_enabled {
            let mut playback_data = playback_buffer.lock().unwrap();
            playback_data.extend_from_slice(input);
        }

        // 累积音频数据
        let mut buffer = buffer.lock().unwrap();
        buffer.extend_from_slice(input);

        // 调整块大小为1秒，确保有足够数据给识别引擎
        let samples_per_second = 16000; // 识别采用16kHz采样率
        let chunk_size = samples_per_second * channels; // 1秒数据

        // 当缓冲区有足够数据时处理
        if buffer.len() >= chunk_size {
            // 获取音频数据块
            let audio_chunk: Vec<f32> = buffer.drain(0..chunk_size).collect();

            // 转换为单声道数据用于语音识别 - 优化处理方式
            let mono_chunk = if channels > 1 {
                let mono_size = chunk_size / channels;
                // 预分配容量以避免动态调整大小
                let mut mono = Vec::with_capacity(mono_size);

                // 使用更高效的向量处理
                for i in 0..mono_size {
                    // 使用滑动窗口而不是循环
                    let slice = &audio_chunk[i * channels..(i + 1) * channels];
                    let avg = slice.iter().sum::<f32>() / channels as f32;
                    mono.push(avg);
                }
                mono
            } else {
                // 已经是单声道
                audio_chunk.clone()
            };

            // 发送数据给转写器
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

        if let Some(stream) = self.output_stream.take() {
            drop(stream);
            info!("已停止音频输出");
        }
    }

    pub fn set_playback_enabled(&mut self, enabled: bool) {
        self.playback_enabled = enabled;
        
        // 如果现在启用了播放但之前没有输出流
        if enabled && self.output_stream.is_none() {
            // 尝试设置输出流
            match self.prepare_output_device() {
                Ok(_) => info!("已启用实时播放并成功设置输出流"),
                Err(e) => warn!("启用实时播放，但设置输出流失败: {}", e),
            }
        } else if !enabled && self.output_stream.is_some() {
            // 如果禁用了播放但有输出流，停止它
            self.output_stream = None;
            info!("已禁用实时播放并停止输出流");
        }
    }
}

impl Drop for AudioCapture {
    fn drop(&mut self) {
        self.stop_capture();
    }
}
