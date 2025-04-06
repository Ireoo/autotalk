use anyhow::Result;
use log::{error, info, warn};
use std::path::Path;
use std::sync::mpsc::{Receiver, Sender};
use std::sync::{Arc, atomic::{AtomicBool, Ordering}};
use std::thread;
use std::time::Duration;

#[cfg(feature = "real_whisper")]
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

pub struct Transcriber {
    model_path: String,
    processing_thread: Option<thread::JoinHandle<()>>,
    should_stop: Arc<AtomicBool>,
    #[cfg(feature = "real_whisper")]
    ctx: Option<WhisperContext>,
}

impl Transcriber {
    pub fn new(model_path: String) -> Self {
        Self {
            model_path,
            processing_thread: None,
            should_stop: Arc::new(AtomicBool::new(false)),
            #[cfg(feature = "real_whisper")]
            ctx: None,
        }
    }

    #[cfg(not(feature = "real_whisper"))]
    pub fn load_model(&mut self) -> Result<()> {
        info!("正在模拟加载语音模型: {}", self.model_path);
        
        // 检查模型文件是否存在
        if !Path::new(&self.model_path).exists() {
            warn!("模型文件不存在: {}，但仍然继续（模拟）", self.model_path);
        }
        
        // 模拟加载延迟，根据模型大小调整
        let model_name = Path::new(&self.model_path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("");
            
        // 根据模型大小调整"加载"时间，让用户感受到差异
        let delay = match model_name {
            "ggml-tiny.bin" => 300,
            "ggml-base.bin" => 500,
            "ggml-small.bin" => 800,
            "ggml-medium-zh.bin" => 1200,
            _ => 300, // demo模型
        };
        
        thread::sleep(Duration::from_millis(delay));
        
        info!("模型加载成功（模拟）");
        
        Ok(())
    }
    
    #[cfg(feature = "real_whisper")]
    pub fn load_model(&mut self) -> Result<()> {
        info!("正在加载语音模型: {}", self.model_path);
        
        // 检查模型文件是否存在
        if !Path::new(&self.model_path).exists() {
            return Err(anyhow::anyhow!("模型文件不存在: {}", self.model_path));
        }
        
        // 加载Whisper模型
        let params = WhisperContextParameters::default();
        match WhisperContext::new_with_params(&self.model_path, params) {
            Ok(ctx) => {
                info!("模型加载成功");
                #[cfg(feature = "real_whisper")]
                self.ctx = Some(ctx);
                Ok(())
            },
            Err(e) => {
                error!("加载模型失败: {:?}", e);
                Err(anyhow::anyhow!("加载模型失败: {:?}", e))
            }
        }
    }
    
    #[cfg(not(feature = "real_whisper"))]
    pub fn start_processing(
        &mut self, 
        audio_rx: Receiver<Vec<f32>>, 
        text_tx: Sender<String>
    ) -> Result<()> {
        // 获取当前使用的模型名称
        let model_name = Path::new(&self.model_path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("未知模型");
            
        info!("启动语音转文字处理线程（模拟）- 使用模型: {}", model_name);
        
        // 重置停止标志
        self.should_stop.store(false, Ordering::SeqCst);
        
        let should_stop = Arc::clone(&self.should_stop);
        let model_path = self.model_path.clone();
        
        let handle = thread::spawn(move || {
            info!("转写线程就绪，等待音频数据（模拟）");
            
            // 基本示例回复，用于演示模型
            let demo_responses = vec![
                "【模拟数据】你好，我是语音识别测试。",
                "【模拟数据】这是一个模拟的语音转写结果。",
                "【模拟数据】AutoTalk正在运行演示模式。",
                "【模拟数据】实际应用中，这里会显示真实的语音识别结果。",
                "【模拟数据】目前使用的是模拟数据，因为没有启用真实模型。",
                "【模拟数据】需要安装必要的依赖才能使用真实模型。",
                "【模拟数据】请参考README文件了解如何安装完整功能。",
            ];
            
            // 模型特定的示例回复
            let model_specific_responses = match Path::new(&model_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("") {
                "ggml-tiny.bin" => vec![
                    "【微型模型模拟】这是微型模型的模拟转写。",
                    "【微型模型模拟】微型模型速度最快但精确度较低。",
                    "【微型模型模拟】适合简单内容和快速响应场景。",
                    "【微型模型模拟】模型体积最小，约75MB。",
                ],
                "ggml-base.bin" => vec![
                    "【基础模型模拟】这是基础模型的模拟转写。",
                    "【基础模型模拟】基础模型在速度和精确度之间取得平衡。",
                    "【基础模型模拟】适合一般场景使用，模型约142MB。",
                    "【基础模型模拟】能识别更复杂的语句和专业词汇。",
                ],
                "ggml-small.bin" => vec![
                    "【小型模型模拟】这是小型模型的模拟转写。",
                    "【小型模型模拟】小型模型提供较高的精确度。",
                    "【小型模型模拟】适合需要更高准确性的场景，模型约466MB。",
                    "【小型模型模拟】能够处理复杂语句和专业术语。",
                ],
                "ggml-medium-zh.bin" => vec![
                    "【中文模型】这是中文优化模型的模拟转写。",
                    "【中文模型】本模型提供最高的中文识别精确度。",
                    "【中文模型】适合要求高准确性的专业场景，模型约1.5GB。",
                    "【中文模型】能够处理方言、专业术语和复杂语境。",
                    "【中文模型】对中文的支持远超其他模型。",
                    "【中文模型】这是一个专为中文优化的语音识别模型。",
                    "【中文模型】能够识别各种中文口音和方言。",
                    "【中文模型】支持繁体字和简体字的识别。",
                ],
                _ => vec![
                    "【演示模型】这是演示模型，仅用于测试UI功能。",
                    "【演示模型】此模型不包含实际识别能力。",
                    "【演示模型】请下载真实的Whisper模型来获得更好体验。",
                    "【演示模型】您可以从\"模型\"按钮中选择并下载其他模型。",
                ],
            };
            
            // 选择要使用的回复列表
            let responses = match Path::new(&model_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("") {
                "ggml-tiny.bin" | "ggml-base.bin" | "ggml-small.bin" | "ggml-medium-zh.bin" => {
                    model_specific_responses
                },
                _ => {
                    // 对于未知或演示模型，使用演示回复
                    demo_responses
                }
            };
            
            let mut response_index = 0;
            
            // 发送初始提示消息
            let model_name = Path::new(&model_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("未知模型");

            let initial_message = format!("【提示】当前使用模拟转写功能，使用模型: {}。若需要真实语音识别，请使用real_whisper特性重新编译。", model_name);
            text_tx.send(initial_message).ok();
            
            while !should_stop.load(Ordering::SeqCst) {
                match audio_rx.recv_timeout(Duration::from_millis(100)) {
                    Ok(_audio_data) => {
                        // 模拟处理时间，不同模型处理时间不同
                        let processing_delay = match Path::new(&model_path)
                            .file_name()
                            .and_then(|n| n.to_str())
                            .unwrap_or("") {
                            "ggml-tiny.bin" => 30,
                            "ggml-base.bin" => 50,
                            "ggml-small.bin" => 70,
                            "ggml-medium-zh.bin" => 100,
                            _ => 40, // demo模型
                        };
                        
                        thread::sleep(Duration::from_millis(processing_delay));
                        
                        // 返回模拟文本
                        let text = responses[response_index].to_string();
                        response_index = (response_index + 1) % responses.len();
                        
                        if let Err(e) = text_tx.send(text) {
                            error!("发送转写文本失败: {}", e);
                            break;
                        }
                    },
                    Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                        // 超时，继续等待
                        continue;
                    },
                    Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                        // 通道已关闭，退出循环
                        info!("音频数据通道已关闭，转写线程退出");
                        break;
                    }
                }
            }
            
            info!("转写线程已结束（模拟）");
        });
        
        self.processing_thread = Some(handle);
        
        Ok(())
    }
    
    #[cfg(feature = "real_whisper")]
    pub fn start_processing(
        &mut self, 
        audio_rx: Receiver<Vec<f32>>, 
        text_tx: Sender<String>
    ) -> Result<()> {
        // 获取当前使用的模型名称
        let model_name = Path::new(&self.model_path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("未知模型");
            
        info!("启动语音转文字处理线程 - 使用模型: {}", model_name);
        
        // 确保模型已加载
        if self.ctx.is_none() {
            return Err(anyhow::anyhow!("模型未加载，无法开始转写"));
        }
        
        // 重置停止标志
        self.should_stop.store(false, Ordering::SeqCst);
        
        let should_stop = Arc::clone(&self.should_stop);
        let ctx = Arc::new(std::sync::Mutex::new(self.ctx.take().unwrap()));
        
        let handle = thread::spawn(move || {
            info!("转写线程就绪，等待音频数据");
            
            // 发送初始提示消息
            let initial_message = format!("【提示】正在使用真实转写功能，使用模型: {}。", model_name);
            text_tx.send(initial_message).ok();
            
            // 准备转写参数
            let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 0 });
            params.set_translate(false); // 不翻译
            params.set_language(Some("zh")); // 设置为中文
            params.set_print_special(false);
            params.set_print_progress(false);
            params.set_print_realtime(false);
            params.set_print_timestamps(false);
            params.set_token_timestamps(true);
            params.set_single_segment(true); // 单段落模式
            
            // 存储已处理的音频，以便累积足够长度再处理
            let mut audio_buffer: Vec<f32> = Vec::with_capacity(16000 * 30); // 预留30秒
            let mut last_process_time = std::time::Instant::now();
            
            while !should_stop.load(Ordering::SeqCst) {
                match audio_rx.recv_timeout(Duration::from_millis(100)) {
                    Ok(audio_data) => {
                        // 累积音频数据
                        audio_buffer.extend_from_slice(&audio_data);
                        
                        // 每隔1秒或缓冲区超过5秒，处理一次音频
                        let buffer_duration = audio_buffer.len() as f32 / 16000.0; // 假设采样率为16kHz
                        let elapsed = last_process_time.elapsed().as_secs_f32();
                        
                        if buffer_duration >= 5.0 || elapsed >= 1.0 {
                            if !audio_buffer.is_empty() {
                                // 锁定上下文进行处理
                                let ctx_guard = match ctx.lock() {
                                    Ok(guard) => guard,
                                    Err(e) => {
                                        error!("获取模型上下文锁失败: {:?}", e);
                                        continue;
                                    }
                                };
                                
                                // 处理音频数据
                                match ctx_guard.full(params.clone(), &audio_buffer) {
                                    Ok(_) => {
                                        // 从模型中获取文本
                                        let num_segments = ctx_guard.full_n_segments();
                                        
                                        for i in 0..num_segments {
                                            if let Ok(segment) = ctx_guard.full_get_segment_text(i) {
                                                let trimmed = segment.trim();
                                                if !trimmed.is_empty() {
                                                    // 发送识别的文本
                                                    if let Err(e) = text_tx.send(trimmed.to_string()) {
                                                        error!("发送转写文本失败: {}", e);
                                                        break;
                                                    }
                                                }
                                            }
                                        }
                                    },
                                    Err(e) => {
                                        error!("处理音频数据失败: {:?}", e);
                                    }
                                }
                                
                                // 清空缓冲区，准备下一批数据
                                audio_buffer.clear();
                                last_process_time = std::time::Instant::now();
                            }
                        }
                    },
                    Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                        // 超时，继续等待
                        continue;
                    },
                    Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                        // 通道已关闭，退出循环
                        info!("音频数据通道已关闭，转写线程退出");
                        break;
                    }
                }
            }
            
            info!("转写线程已结束");
        });
        
        self.processing_thread = Some(handle);
        
        Ok(())
    }
    
    pub fn stop(&mut self) {
        // 设置停止标志
        self.should_stop.store(true, Ordering::SeqCst);
        
        if let Some(handle) = self.processing_thread.take() {
            // 等待线程结束
            match handle.join() {
                Ok(_) => info!("转写线程正常结束"),
                Err(e) => error!("转写线程异常终止: {:?}", e),
            }
        }
    }
}

impl Drop for Transcriber {
    fn drop(&mut self) {
        self.stop();
    }
} 