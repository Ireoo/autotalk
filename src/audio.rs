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
        info!("正在获取可用音频设备列表");
        let devices = self.host.devices().context("无法获取音频设备列表")?;
        let device_names: Vec<String> = devices
            .filter_map(|device| {
                device
                    .name()
                    .map(|name| name.to_string())
                    .ok()
            })
            .collect();

        if device_names.is_empty() {
            warn!("未发现可用音频设备");
        } else {
            info!("发现 {} 个音频设备", device_names.len());
            for (i, name) in device_names.iter().enumerate() {
                debug!("设备 {}: {}", i, name);
            }
        }

        Ok(device_names)
    }

    pub fn select_device(&mut self, device_name: Option<String>) -> Result<()> {
        self.device = match device_name {
            Some(name) => {
                info!("尝试使用指定设备: {}", name);
                let device = self.host
                    .devices()?
                    .find(|device| {
                        device
                            .name()
                            .map(|device_name| device_name == name)
                            .unwrap_or(false)
                    });
                    
                if device.is_none() {
                    warn!("未找到指定设备: {}, 将尝试使用默认设备", name);
                    Some(self.host
                        .default_input_device()
                        .context("未找到默认输入设备")?)
                } else {
                    info!("成功找到指定设备: {}", name);
                    device
                }
            }
            None => {
                info!("使用默认输入设备");
                Some(self.host
                    .default_input_device()
                    .context("未找到默认输入设备")?)
            }
        };

        match self.device.as_ref().unwrap().name() {
            Ok(device_name) => {
                info!("已选择音频设备: {}", device_name);
            },
            Err(e) => {
                warn!("无法获取所选设备名称: {}", e);
            }
        }

        Ok(())
    }

    pub fn start_capture(&mut self, tx: mpsc::Sender<Vec<f32>>) -> Result<()> {
        info!("开始启动音频捕获流程");
        self.tx = Some(tx);
        let device = self.device.as_ref().context("未选择音频设备")?;

        // 获取设备支持的配置
        info!("查询设备支持的配置");
        let supported_configs = device.supported_input_configs()?;
        
        // 转换为Vec以便调试
        let config_vec: Vec<_> = supported_configs.collect();
        if config_vec.is_empty() {
            return Err(anyhow::anyhow!("设备不支持任何输入配置"));
        }
        
        debug!("设备支持 {} 种配置:", config_vec.len());
        for (i, cfg) in config_vec.iter().enumerate() {
            debug!("配置 {}: 通道数: {}, 采样率: {} - {} Hz", 
                i, cfg.channels(), 
                cfg.min_sample_rate().0, cfg.max_sample_rate().0);
        }
        
        // 找到合适的配置
        let config = config_vec.into_iter()
            .filter(|config| config.channels() == self.channels)
            .max_by_key(|config| config.max_sample_rate().0)
            .context("未找到合适的音频配置")?
            .with_sample_rate(cpal::SampleRate(self.sample_rate));

        info!(
            "已选择音频配置: {}Hz, {} 通道",
            config.sample_rate().0,
            config.channels()
        );

        let err_fn = |err| error!("音频流错误: {}", err);
        let buffer = Arc::clone(&self.buffer);
        let sender = self.tx.clone().unwrap();

        // 创建音频处理回调
        info!("创建音频处理流，格式: {:?}", config.sample_format());
        let stream = match config.sample_format() {
            SampleFormat::F32 => {
                info!("使用F32采样格式");
                device.build_input_stream(
                    &config.into(),
                    move |data: &[f32], _: &_| {
                        Self::process_audio_data(data, Arc::clone(&buffer), &sender);
                    },
                    err_fn,
                    None,
                )
            },
            SampleFormat::I16 => {
                info!("使用I16采样格式");
                device.build_input_stream(
                    &config.into(),
                    move |data: &[i16], _: &_| {
                        let float_data: Vec<f32> = data.iter().map(|&s| s as f32 / 32768.0).collect();
                        Self::process_audio_data(&float_data, Arc::clone(&buffer), &sender);
                    },
                    err_fn,
                    None,
                )
            },
            SampleFormat::U16 => {
                info!("使用U16采样格式");
                device.build_input_stream(
                    &config.into(),
                    move |data: &[u16], _: &_| {
                        let float_data: Vec<f32> = data
                            .iter()
                            .map(|&s| ((s as f32) / 32768.0) - 1.0)
                            .collect();
                        Self::process_audio_data(&float_data, Arc::clone(&buffer), &sender);
                    },
                    err_fn,
                    None,
                )
            },
            _ => {
                let err = format!("不支持的采样格式: {:?}", config.sample_format());
                error!("{}", err);
                return Err(anyhow::anyhow!(err));
            }
        }?;

        info!("音频流创建成功，启动播放");
        stream.play()?;
        self.stream = Some(stream);
        info!("开始捕获音频");

        Ok(())
    }

    fn process_audio_data(
        input: &[f32],
        buffer: Arc<Mutex<Vec<f32>>>,
        sender: &mpsc::Sender<Vec<f32>>,
    ) {
        // 累积音频数据
        let mut buffer = buffer.lock().unwrap();
        buffer.extend_from_slice(input);

        // 每积累一定量的音频数据，发送一次进行处理
        // 对应约1秒的48kHz音频，考虑到有2个通道
        const CHUNK_SIZE: usize = 48000 * 2;
        if buffer.len() >= CHUNK_SIZE {
            // 获取音频数据块
            let audio_chunk: Vec<f32> = buffer.drain(0..CHUNK_SIZE).collect();
            
            // 对于双声道音频，通过平均左右声道转换为单声道
            // 这样转写器仍然可以处理单声道数据
            let mono_chunk: Vec<f32> = if CHUNK_SIZE % 2 == 0 {
                let mut mono = Vec::with_capacity(CHUNK_SIZE / 2);
                for i in 0..CHUNK_SIZE/2 {
                    // 平均左右声道
                    mono.push((audio_chunk[i*2] + audio_chunk[i*2+1]) * 0.5);
                }
                mono
            } else {
                // 如果数据不完整，保持原样
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