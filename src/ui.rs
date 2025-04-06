use crate::audio::AudioCapture;
use crate::downloader::{get_default_resources, get_resource_display_name, DownloadResource, DownloadStatus, Downloader};
use crate::transcriber::Transcriber;
use anyhow::{Context, Result};
use eframe::{App, CreationContext, Frame};
use egui::{
    Align, Button, Color32, Context as EguiContext, FontData, FontDefinitions, FontFamily, Layout,
    ProgressBar, RichText, ScrollArea, TextEdit, Ui, Vec2,
};
use log::{debug, error, info, warn};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::thread;
use std::time::{Duration, Instant};
use arboard;

pub struct AutoTalkApp {
    model_path: String,
    device_name: Option<String>,
    audio_capture: Option<AudioCapture>,
    transcriber: Option<Transcriber>,
    text_receiver: Option<Receiver<String>>,
    transcript: String,
    status: String,
    recording: bool,
    last_update: Instant,
    settings_open: bool,
    models_window_open: bool,  // 新增：模型管理窗口开关
    available_devices: Vec<String>,
    selected_device_idx: Option<usize>,
    copy_status: String,
    auto_scroll: bool,
    
    // 资源下载相关
    skip_download: bool,
    download_status_receiver: Option<Receiver<DownloadStatus>>,
    download_statuses: HashMap<String, DownloadStatus>,
    resources: Vec<DownloadResource>,
    selected_model_idx: usize,
    downloading: bool,
    download_complete: bool,
    download_window_open: bool,
    model_file_exists: bool,
    font_file_exists: bool,
}

impl AutoTalkApp {
    fn new(model_path: String, device_name: Option<String>, skip_download: bool) -> Self {
        // 判断必要文件是否已存在
        let model_file = Path::new(&model_path);
        let model_file_exists = Downloader::check_file_exists(model_file);
        
        let font_path = Path::new("assets/NotoSansSC-Regular.ttf");
        let font_file_exists = Downloader::check_file_exists(font_path);
        
        // 获取可下载的资源列表
        let resources = get_default_resources();
        
        // 查找默认模型在资源列表中的索引
        let model_filename = model_file.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("ggml-small.bin");
            
        let selected_model_idx = resources.iter()
            .position(|r| r.name == model_filename)
            .unwrap_or(0);
        
        // 根据是否跳过下载或文件是否存在，决定是否显示下载窗口
        let download_window_open = !skip_download && (!model_file_exists || !font_file_exists);

        Self {
            model_path,
            device_name,
            audio_capture: None,
            transcriber: None,
            text_receiver: None,
            transcript: String::new(),
            status: "准备就绪".to_string(),
            recording: false,
            last_update: Instant::now(),
            settings_open: false,
            models_window_open: false,  // 初始化为关闭状态
            available_devices: Vec::new(),
            selected_device_idx: None,
            copy_status: String::new(),
            auto_scroll: true,
            
            skip_download,
            download_status_receiver: None,
            download_statuses: HashMap::new(),
            resources,
            selected_model_idx,
            downloading: false,
            download_complete: false,
            download_window_open,
            model_file_exists,
            font_file_exists,
        }
    }

    fn init_audio_capture(&mut self) -> Result<()> {
        info!("正在初始化音频捕获...");
        
        let mut audio = match AudioCapture::new() {
            Ok(audio) => {
                info!("创建AudioCapture实例成功");
                audio
            },
            Err(e) => {
                error!("创建AudioCapture实例失败: {}", e);
                self.status = format!("初始化音频失败: {}", e);
                return Err(anyhow::anyhow!("创建AudioCapture实例失败: {}", e));
            }
        };
        
        // 列出可用设备
        match audio.list_devices() {
            Ok(devices) => {
                self.available_devices = devices;
                info!("发现 {} 个音频设备", self.available_devices.len());
            },
            Err(e) => {
                warn!("无法列出音频设备: {}", e);
                self.status = format!("无法列出音频设备: {}", e);
                // 继续执行，因为这不是致命错误
            }
        }
        
        // 如果指定了设备名称，查找其索引
        if let Some(ref device_name) = self.device_name {
            info!("尝试使用指定设备: {}", device_name);
            self.selected_device_idx = self.available_devices
                .iter()
                .position(|name| name == device_name);
            
            if self.selected_device_idx.is_none() {
                warn!("找不到指定的设备: {}", device_name);
            }
        }
        
        // 选择设备
        match audio.select_device(self.device_name.clone()) {
            Ok(_) => {
                info!("成功选择音频设备");
            },
            Err(e) => {
                error!("选择音频设备失败: {}", e);
                self.status = format!("选择音频设备失败: {}", e);
                return Err(anyhow::anyhow!("选择音频设备失败: {}", e));
            }
        }
        
        self.audio_capture = Some(audio);
        self.status = "初始化音频捕获成功".to_string();
        
        Ok(())
    }

    fn init_transcriber(&mut self) -> Result<()> {
        let mut transcriber = Transcriber::new(self.model_path.clone());
        transcriber.load_model()?;
        
        self.transcriber = Some(transcriber);
        self.status = "初始化语音模型成功".to_string();
        
        Ok(())
    }

    fn start_recording(&mut self) -> Result<()> {
        info!("开始录音...");
        
        if self.recording {
            info!("已经在录音中，忽略请求");
            return Ok(());
        }
        
        if self.audio_capture.is_none() {
            info!("音频捕获未初始化，尝试初始化");
            match self.init_audio_capture() {
                Ok(_) => info!("成功初始化音频捕获"),
                Err(e) => {
                    error!("初始化音频捕获失败: {}", e);
                    self.status = format!("无法启动录音: {}", e);
                    return Err(anyhow::anyhow!("无法启动录音: {}", e));
                }
            }
        }
        
        if self.transcriber.is_none() {
            info!("转写器未初始化，尝试初始化");
            match self.init_transcriber() {
                Ok(_) => info!("成功初始化转写器"),
                Err(e) => {
                    error!("初始化转写器失败: {}", e);
                    self.status = format!("无法启动转写: {}", e);
                    return Err(anyhow::anyhow!("无法启动转写: {}", e));
                }
            }
        }
        
        // 创建音频和文本的通道
        let (audio_tx, audio_rx) = mpsc::channel();
        let (text_tx, text_rx) = mpsc::channel();
        
        // 启动音频捕获
        match self.audio_capture
            .as_mut()
            .unwrap()
            .start_capture(audio_tx) {
            Ok(_) => info!("成功启动音频捕获"),
            Err(e) => {
                error!("启动音频捕获失败: {}", e);
                self.status = format!("启动录音失败: {}", e);
                return Err(anyhow::anyhow!("启动录音失败: {}", e));
            }
        }
        
        // 启动转写处理
        match self.transcriber
            .as_mut()
            .unwrap()
            .start_processing(audio_rx, text_tx) {
            Ok(_) => info!("成功启动转写处理"),
            Err(e) => {
                error!("启动转写处理失败: {}", e);
                // 停止已经启动的音频捕获
                if let Some(audio) = self.audio_capture.as_mut() {
                    audio.stop_capture();
                }
                self.status = format!("启动转写失败: {}", e);
                return Err(anyhow::anyhow!("启动转写失败: {}", e));
            }
        }
        
        self.text_receiver = Some(text_rx);
        self.recording = true;
        self.status = "正在录音和转写...".to_string();
        info!("成功启动录音和转写");
        
        Ok(())
    }

    fn stop_recording(&mut self) {
        if !self.recording {
            return;
        }
        
        // 停止音频捕获
        if let Some(audio) = self.audio_capture.as_mut() {
            audio.stop_capture();
        }
        
        // 停止转写处理
        if let Some(transcriber) = self.transcriber.as_mut() {
            transcriber.stop();
        }
        
        self.recording = false;
        self.text_receiver = None;
        self.status = "已停止录音".to_string();
    }

    fn update_transcript(&mut self) {
        if let Some(ref receiver) = self.text_receiver {
            loop {
                match receiver.try_recv() {
                    Ok(text) => {
                        if !text.trim().is_empty() {
                            if !self.transcript.is_empty() {
                                self.transcript.push(' ');
                            }
                            self.transcript.push_str(&text);
                            self.last_update = Instant::now();
                        }
                    }
                    Err(TryRecvError::Empty) => break,
                    Err(TryRecvError::Disconnected) => {
                        self.status = "转写处理已断开".to_string();
                        self.recording = false;
                        self.text_receiver = None;
                        break;
                    }
                }
            }
        }
    }

    fn clear_transcript(&mut self) {
        self.transcript.clear();
        self.status = "已清空转写记录".to_string();
    }

    fn copy_to_clipboard(&mut self) {
        if !self.transcript.is_empty() {
            match arboard::Clipboard::new().and_then(|mut clipboard| {
                clipboard.set_text(&self.transcript)
            }) {
                Ok(_) => {
                    self.copy_status = "已复制到剪贴板".to_string();
                },
                Err(e) => {
                    self.copy_status = format!("复制失败: {}", e);
                }
            }
            
            // 2秒后清除状态
            let handle = thread::spawn(|| {
                thread::sleep(Duration::from_secs(2));
            });
            
            handle.join().ok();
        } else {
            self.copy_status = "没有可复制的文本".to_string();
        }
    }
    
    // 开始下载资源
    fn start_download(&mut self) -> Result<()> {
        if self.downloading {
            return Ok(());
        }
        
        // 创建下载状态通道
        let (status_tx, status_rx) = mpsc::channel();
        self.download_status_receiver = Some(status_rx);
        
        // 筛选需要下载的资源
        let mut resources_to_download = Vec::new();
        
        // 添加选中的模型
        if let Some(model_resource) = self.resources.get(self.selected_model_idx) {
            resources_to_download.push(model_resource.clone());
        }
        
        // 添加字体资源
        if let Some(font_resource) = self.resources.iter().find(|r| r.name.ends_with(".ttf")) {
            resources_to_download.push(font_resource.clone());
        }
        
        // 启动下载线程
        let status_tx_clone = status_tx.clone();
        tokio::spawn(async move {
            let downloader = Downloader::new();
            
            for resource in resources_to_download {
                let resource_name = resource.name.clone();
                
                // 更新状态为下载中
                status_tx_clone
                    .send(DownloadStatus::Pending(resource_name.clone()))
                    .ok();
                
                match downloader.download_file(&resource, status_tx_clone.clone()).await {
                    Ok(_) => {
                        // 下载成功由download_file函数发送状态
                    }
                    Err(e) => {
                        error!("下载 {} 失败: {}", resource_name, e);
                        status_tx_clone
                            .send(DownloadStatus::Failed(
                                resource_name,
                                format!("下载失败: {}", e),
                            ))
                            .ok();
                    }
                }
            }
            
            // 通知下载完成
            status_tx_clone.send(DownloadStatus::Completed("__all__".to_string(), PathBuf::new())).ok();
        });
        
        self.downloading = true;
        Ok(())
    }
    
    // 更新下载状态
    fn update_download_status(&mut self) {
        if let Some(ref receiver) = self.download_status_receiver {
            loop {
                match receiver.try_recv() {
                    Ok(status) => {
                        match &status {
                            DownloadStatus::Completed(name, _) if name == "__all__" => {
                                // 特殊标记，表示所有下载已完成
                                self.downloading = false;
                                self.download_complete = true;
                                
                                // 更新模型路径
                                if let Some(model_resource) = self.resources.get(self.selected_model_idx) {
                                    self.model_path = model_resource.target_path.to_string_lossy().to_string();
                                }
                                
                                debug!("所有下载完成，模型路径更新为: {}", self.model_path);
                                break;
                            }
                            DownloadStatus::Completed(name, _) => {
                                // 单个文件下载完成
                                info!("{} 下载完成", name);
                                
                                // 更新文件存在状态
                                if name.ends_with(".bin") {
                                    self.model_file_exists = true;
                                } else if name.ends_with(".ttf") {
                                    self.font_file_exists = true;
                                }
                            }
                            _ => {}
                        }
                        
                        // 更新状态映射
                        let name = match &status {
                            DownloadStatus::Pending(name) => name.clone(),
                            DownloadStatus::Downloading(name, _) => name.clone(),
                            DownloadStatus::Completed(name, _) => name.clone(),
                            DownloadStatus::Failed(name, _) => name.clone(),
                            DownloadStatus::Skipped(name) => name.clone(),
                            DownloadStatus::Progress(name, _) => name.clone(),
                            DownloadStatus::Complete(name) => name.clone(),
                        };
                        
                        if name != "__all__" {
                            self.download_statuses.insert(name, status);
                        }
                    }
                    Err(TryRecvError::Empty) => break,
                    Err(TryRecvError::Disconnected) => {
                        error!("下载状态通道已断开");
                        self.downloading = false;
                        self.download_status_receiver = None;
                        break;
                    }
                }
            }
        }
    }
    
    // 显示下载窗口
    fn show_download_window(&mut self, ctx: &EguiContext) {
        if !self.download_window_open {
            return;
        }
        
        egui::Window::new("下载必要资源")
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ctx, |ui| {
                ui.add_space(10.0);
                ui.heading("AutoTalk 需要下载必要资源");
                ui.add_space(10.0);
                
                ui.label("选择要使用的 Whisper 模型:");
                ui.add_space(5.0);
                
                egui::ComboBox::from_label("")
                    .selected_text(get_resource_display_name(&self.resources[self.selected_model_idx].name))
                    .show_ui(ui, |ui| {
                        for (idx, resource) in self.resources.iter().enumerate() {
                            if resource.name.ends_with(".bin") {
                                ui.selectable_value(
                                    &mut self.selected_model_idx,
                                    idx,
                                    get_resource_display_name(&resource.name),
                                );
                            }
                        }
                    });
                
                ui.add_space(10.0);
                
                // 显示资源下载状态
                if !self.download_statuses.is_empty() || self.downloading {
                    ui.separator();
                    ui.add_space(5.0);
                    ui.heading("下载状态");
                    ui.add_space(5.0);
                    
                    // 显示模型下载状态
                    if let Some(model_resource) = self.resources.get(self.selected_model_idx) {
                        self.show_resource_status(ui, &model_resource.name);
                    }
                    
                    // 显示字体下载状态
                    if let Some(font_resource) = self.resources.iter().find(|r| r.name.ends_with(".ttf")) {
                        self.show_resource_status(ui, &font_resource.name);
                    }
                    
                    ui.add_space(5.0);
                }
                
                ui.separator();
                ui.add_space(10.0);
                
                ui.with_layout(Layout::right_to_left(Align::TOP), |ui| {
                    if self.download_complete {
                        // 下载完成，显示继续按钮
                        if ui.button("继续").clicked() {
                            self.download_window_open = false;
                        }
                    } else if self.downloading {
                        // 正在下载，显示取消按钮
                        if ui.add_enabled(false, Button::new("正在下载...")).clicked() {
                            // 这里不会执行，因为按钮被禁用了
                        }
                    } else {
                        // 准备下载，显示开始下载按钮
                        if ui.button("开始下载").clicked() {
                            if let Err(e) = self.start_download() {
                                error!("启动下载失败: {}", e);
                                self.status = format!("启动下载失败: {}", e);
                            }
                        }
                        
                        ui.add_space(10.0);
                        
                        // 跳过下载按钮
                        if ui.button("跳过(不推荐)").clicked() {
                            self.download_window_open = false;
                        }
                    }
                });
            });
    }
    
    // 显示单个资源的下载状态
    fn show_resource_status(&self, ui: &mut Ui, resource_name: &str) {
        let _display_name = get_resource_display_name(resource_name);
        
        match self.download_statuses.get(resource_name) {
            Some(DownloadStatus::Pending(_)) => {
                ui.add(ProgressBar::new(0.0).animate(true).show_percentage());
                ui.label("等待下载...");
            },
            Some(DownloadStatus::Downloading(_, progress)) => {
                ui.add(ProgressBar::new(*progress).animate(true).show_percentage());
                ui.label(format!("下载中... {:.1}%", progress * 100.0));
            },
            Some(DownloadStatus::Completed(_, _)) => {
                ui.add(ProgressBar::new(1.0).fill(Color32::from_rgb(0, 180, 0)));
                ui.label("已下载");
            },
            Some(DownloadStatus::Progress(_, progress)) => {
                ui.add(ProgressBar::new(*progress).animate(true).show_percentage());
                ui.label(format!("下载中... {:.1}%", progress * 100.0));
            },
            Some(DownloadStatus::Complete(_)) => {
                ui.add(ProgressBar::new(1.0).fill(Color32::from_rgb(0, 180, 0)));
                ui.label("已下载");
            },
            Some(DownloadStatus::Failed(_, error)) => {
                ui.add(ProgressBar::new(0.0).fill(Color32::from_rgb(180, 0, 0)));
                ui.label(RichText::new(format!("下载失败: {}", error)).color(Color32::from_rgb(180, 0, 0)));
            },
            Some(DownloadStatus::Skipped(_)) => {
                ui.add(ProgressBar::new(1.0).fill(Color32::from_rgb(0, 180, 0)));
                ui.label("已跳过（文件已存在）");
            },
            None => {
                ui.add(ProgressBar::new(0.0));
                ui.label("尚未开始下载");
            },
        }
        
        ui.add_space(5.0);
    }

    // 添加模型管理窗口
    fn show_models_window(&mut self, ctx: &EguiContext) {
        if !self.models_window_open {
            return;
        }

        egui::Window::new("模型管理")
            .collapsible(false)
            .resizable(true)
            .min_width(500.0)
            .show(ctx, |ui| {
                ui.add_space(10.0);
                ui.heading("可用的语音模型");
                ui.add_space(5.0);
                
                ui.horizontal(|ui| {
                    ui.label("当前使用模型：");
                    let current_model_name = Path::new(&self.model_path)
                        .file_name()
                        .and_then(|n| n.to_str())
                        .map(|name| get_resource_display_name(name))
                        .unwrap_or_else(|| "未知模型".to_string());
                    ui.label(RichText::new(current_model_name).strong().color(Color32::GREEN));
                });
                
                ui.add_space(10.0);
                ui.separator();
                ui.add_space(5.0);
                
                // 模型说明
                ui.collapsing("模型说明", |ui| {
                    ui.add_space(5.0);
                    ui.label("AutoTalk支持多种不同大小和精度的Whisper模型：");
                    ui.add_space(5.0);
                    
                    let text_color = Color32::from_rgb(220, 220, 220);
                    ui.label(RichText::new("• 微型模型(tiny)：最小、最快，但准确度较低").color(text_color));
                    ui.label(RichText::new("• 基础模型(base)：平衡大小和准确度").color(text_color));
                    ui.label(RichText::new("• 小型模型(small)：较好的准确度，资源占用适中").color(text_color));
                    ui.label(RichText::new("• 中文优化模型(medium-zh)：最高的准确度，支持更复杂的中文识别").color(text_color));
                    
                    ui.add_space(5.0);
                    ui.label("注意：模型越大，占用内存和CPU资源越多，但识别准确度越高。");
                    ui.label("您可以根据设备性能和需求选择合适的模型。");
                });
                
                ui.add_space(5.0);

                // 创建一个模型资源的可变副本，这样闭包不会直接引用self.resources
                let model_resources: Vec<DownloadResource> = self.resources.iter()
                    .filter(|r| r.name.ends_with(".bin"))
                    .cloned()
                    .collect();
                    
                // 保存当前模型路径、下载状态等需要的信息
                let current_model_path = self.model_path.clone();
                let is_downloading = self.downloading;
                let download_statuses = self.download_statuses.clone();

                egui::ScrollArea::vertical().max_height(300.0).show(ui, |ui| {
                    for (idx, resource) in model_resources.iter().enumerate() {
                        ui.push_id(idx, |ui| {
                            ui.add_space(2.0);
                            let model_name = get_resource_display_name(&resource.name);
                            let model_path = &resource.target_path;
                            let model_exists = Downloader::check_file_exists(model_path);
                            
                            // 计算模型大小的可读表示
                            let size_display = if let Some(size) = resource.file_size {
                                if size > 1_000_000_000 {
                                    format!("{:.1} GB", size as f64 / 1_000_000_000.0)
                                } else if size > 1_000_000 {
                                    format!("{:.1} MB", size as f64 / 1_000_000.0)
                                } else if size > 1_000 {
                                    format!("{:.1} KB", size as f64 / 1_000.0)
                                } else {
                                    format!("{} Bytes", size)
                                }
                            } else {
                                "未知大小".to_string()
                            };

                            // 检查是否为当前选中的模型
                            let is_current = current_model_path == model_path.to_string_lossy();
                            let model_name_str = model_name.clone();
                            
                            ui.horizontal(|ui| {
                                let text = if is_current {
                                    RichText::new(format!("▶ {}", model_name)).strong().color(Color32::GREEN)
                                } else {
                                    RichText::new(model_name)
                                };

                                ui.label(text);
                                ui.add_space(5.0);
                                ui.label(RichText::new(format!("({})", size_display)).weak());
                                
                                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                                    if model_exists {
                                        if !is_current && ui.button("使用").clicked() {
                                            // 存储所需变更，后续应用
                                            self.selected_model_idx = self.resources.iter()
                                                .position(|r| r.name == resource.name)
                                                .unwrap_or(self.selected_model_idx);
                                            self.model_path = model_path.to_string_lossy().to_string();
                                            
                                            // 重置转写器，使用新模型
                                            if self.transcriber.is_some() {
                                                self.stop_recording();
                                                self.transcriber = None;
                                                let _ = self.init_transcriber();
                                                self.status = format!("已切换到模型: {}", model_name_str);
                                            }
                                        }
                                    } else {
                                        if is_downloading && download_statuses.contains_key(&resource.name) {
                                            match download_statuses.get(&resource.name) {
                                                Some(DownloadStatus::Pending(_)) => {
                                                    ui.label("等待下载...");
                                                },
                                                Some(DownloadStatus::Downloading(_, progress)) => {
                                                    ui.label(format!("下载中 {:.0}%", progress * 100.0));
                                                },
                                                Some(DownloadStatus::Failed(_, _)) => {
                                                    if ui.button("重试").clicked() {
                                                        let _ = self.start_download_single_model(&resource);
                                                    }
                                                },
                                                _ => {
                                                    if ui.button("下载").clicked() {
                                                        let _ = self.start_download_single_model(&resource);
                                                    }
                                                }
                                            }
                                        } else {
                                            if ui.button("下载").clicked() {
                                                let _ = self.start_download_single_model(&resource);
                                            }
                                        }
                                    }
                                });
                            });

                            // 显示下载状态
                            if !model_exists && download_statuses.contains_key(&resource.name) {
                                match download_statuses.get(&resource.name) {
                                    Some(DownloadStatus::Downloading(_, progress)) => {
                                        ui.add(ProgressBar::new(*progress).show_percentage());
                                    },
                                    Some(DownloadStatus::Failed(_, error)) => {
                                        ui.label(RichText::new(format!("错误: {}", error)).color(Color32::RED));
                                    },
                                    _ => {}
                                }
                            }
                            ui.add_space(2.0);
                            if idx < model_resources.len() - 1 {
                                ui.separator();
                            }
                        });
                    }
                });

                ui.add_space(10.0);
                ui.separator();
                ui.add_space(5.0);

                ui.horizontal(|ui| {
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if ui.button("关闭").clicked() {
                            self.models_window_open = false;
                        }
                    });
                });
            });
    }

    // 下载单个模型
    fn start_download_single_model(&mut self, resource: &DownloadResource) -> Result<()> {
        if self.downloading && !self.download_complete {
            return Ok(());
        }
        
        // 创建下载状态通道
        let (status_tx, status_rx) = mpsc::channel();
        self.download_status_receiver = Some(status_rx);
        
        // 更新状态字典，标记为等待下载
        self.download_statuses.insert(
            resource.name.clone(), 
            DownloadStatus::Pending(resource.name.clone())
        );
        
        // 启动下载线程
        let resource_clone = resource.clone();
        let status_tx_clone = status_tx.clone();
        tokio::spawn(async move {
            let downloader = Downloader::new();
            
            status_tx_clone
                .send(DownloadStatus::Pending(resource_clone.name.clone()))
                .ok();
            
            match downloader.download_file(&resource_clone, status_tx_clone.clone()).await {
                Ok(_) => {
                    // 下载成功由download_file函数发送状态
                }
                Err(e) => {
                    error!("下载 {} 失败: {}", resource_clone.name, e);
                    status_tx_clone
                        .send(DownloadStatus::Failed(
                            resource_clone.name,
                            format!("下载失败: {}", e),
                        ))
                        .ok();
                }
            }
            
            // 通知下载完成
            status_tx_clone.send(DownloadStatus::Completed("__all__".to_string(), PathBuf::new())).ok();
        });
        
        self.downloading = true;
        self.download_complete = false;
        Ok(())
    }
}

impl App for AutoTalkApp {
    fn update(&mut self, ctx: &EguiContext, _frame: &mut Frame) {
        // 设置刷新率，确保UI响应及时
        ctx.request_repaint_after(Duration::from_millis(100));
        
        // 更新下载状态
        self.update_download_status();
        
        // 显示下载窗口
        self.show_download_window(ctx);
        
        // 显示模型管理窗口
        self.show_models_window(ctx);
        
        // 如果下载窗口打开，不显示主界面
        if self.download_window_open {
            return;
        }
        
        // 更新转写内容
        self.update_transcript();
        
        // 在状态栏上显示当前模型名称
        let model_name = Path::new(&self.model_path)
            .file_name()
            .and_then(|n| n.to_str())
            .map(|name| get_resource_display_name(name))
            .unwrap_or_else(|| "未知模型".to_string());
        
        // 顶部导航栏
        egui::TopBottomPanel::top("top_panel").show(ctx, |ui| {
            egui::menu::bar(ui, |ui| {
                ui.add_space(10.0);
                ui.heading("AutoTalk 实时语音转文字");
                ui.add_space(20.0);
                
                if ui.button(if self.recording { "停止录音" } else { "开始录音" }).clicked() {
                    if self.recording {
                        self.stop_recording();
                    } else {
                        if let Err(e) = self.start_recording() {
                            self.status = format!("启动失败: {}", e);
                        }
                    }
                }
                
                ui.add_space(10.0);
                if ui.button("清空").clicked() {
                    self.clear_transcript();
                }
                
                ui.add_space(10.0);
                if ui.button("复制").clicked() {
                    self.copy_to_clipboard();
                }
                
                ui.add_space(10.0);
                if ui.button("模型").clicked() {
                    self.models_window_open = !self.models_window_open;
                }
                
                ui.add_space(10.0);
                if ui.button("设置").clicked() {
                    self.settings_open = !self.settings_open;
                }
                
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let status_color = if self.recording {
                        Color32::from_rgb(0, 180, 0)
                    } else {
                        Color32::from_rgb(100, 100, 100)
                    };
                    
                    ui.add_space(20.0);
                    ui.label(RichText::new(&self.status).color(status_color));
                    
                    ui.add_space(10.0);
                    ui.label(RichText::new(format!("模型: {}", model_name)).monospace());
                    
                    if !self.copy_status.is_empty() {
                        ui.add_space(20.0);
                        ui.label(&self.copy_status);
                    }
                });
            });
        });
        
        // 设置窗口
        if self.settings_open {
            egui::Window::new("设置")
                .collapsible(false)
                .resizable(false)
                .show(ctx, |ui| {
                    ui.add_space(5.0);
                    ui.checkbox(&mut self.auto_scroll, "自动滚动");
                    ui.add_space(10.0);
                    
                    ui.label("Whisper模型路径:");
                    ui.text_edit_singleline(&mut self.model_path);
                    ui.add_space(10.0);
                    
                    ui.label("音频设备:");
                    
                    egui::ComboBox::from_label("")
                        .selected_text(
                            self.selected_device_idx
                                .and_then(|idx| self.available_devices.get(idx))
                                .unwrap_or(&"默认设备".to_string()),
                        )
                        .show_ui(ui, |ui| {
                            ui.selectable_value(&mut self.selected_device_idx, None, "默认设备");
                            for (idx, name) in self.available_devices.iter().enumerate() {
                                ui.selectable_value(&mut self.selected_device_idx, Some(idx), name);
                            }
                        });
                    
                    ui.add_space(10.0);
                    if ui.button("应用并重启").clicked() {
                        // 停止现有的录音
                        self.stop_recording();
                        
                        // 更新设备名称
                        self.device_name = self.selected_device_idx
                            .and_then(|idx| self.available_devices.get(idx))
                            .cloned();
                        
                        // 重置音频捕获和转写器
                        self.audio_capture = None;
                        self.transcriber = None;
                        
                        // 尝试重新初始化
                        let _ = self.init_audio_capture();
                        let _ = self.init_transcriber();
                        
                        self.settings_open = false;
                    }
                    
                    ui.add_space(5.0);
                    if ui.button("关闭").clicked() {
                        self.settings_open = false;
                    }
                });
        }
        
        // 主内容区域
        egui::CentralPanel::default().show(ctx, |ui| {
            let text_height = ui.available_height();
            
            ui.add_space(5.0);
            
            ScrollArea::vertical()
                .auto_shrink([false, false])
                .stick_to_bottom(self.auto_scroll)
                .show(ui, |ui| {
                    let text_edit = TextEdit::multiline(&mut self.transcript)
                        .font(egui::TextStyle::Monospace)
                        .desired_width(f32::INFINITY)
                        .desired_rows(20)
                        .min_size(Vec2::new(ui.available_width(), text_height - 20.0))
                        .lock_focus(true);
                    
                    ui.add(text_edit);
                });
            
            ui.add_space(5.0);
        });
    }
}

// 配置字体和UI
fn configure_ui(ctx: &CreationContext) {
    let mut fonts = FontDefinitions::default();
    
    // 添加中文字体支持
    let font_path = Path::new("assets/NotoSansSC-Regular.ttf");
    if font_path.exists() {
        match fs::read(font_path) {
            Ok(font_data) => {
                fonts.font_data.insert(
                    "chinese_font".to_owned(),
                    FontData::from_owned(font_data),
                );
                
                // 设置字体优先级
                fonts
                    .families
                    .get_mut(&FontFamily::Proportional)
                    .unwrap()
                    .insert(0, "chinese_font".to_owned());
                
                fonts
                    .families
                    .get_mut(&FontFamily::Monospace)
                    .unwrap()
                    .insert(0, "chinese_font".to_owned());
                    
                info!("已加载中文字体");
            }
            Err(e) => {
                warn!("无法加载中文字体: {}", e);
            }
        }
    } else {
        warn!("中文字体文件不存在，UI中文可能显示为乱码");
    }
    
    ctx.egui_ctx.set_fonts(fonts);
}

pub async fn run_app(model_path: String, device_name: Option<String>, skip_download: bool) -> Result<()> {
    // 确保目录存在
    let models_dir = Path::new("models");
    if !models_dir.exists() {
        info!("创建模型目录: {}", models_dir.display());
        fs::create_dir_all(models_dir).context("无法创建模型目录")?;
    }
    
    let assets_dir = Path::new("assets");
    if !assets_dir.exists() {
        info!("创建资源目录: {}", assets_dir.display());
        fs::create_dir_all(assets_dir).context("无法创建资源目录")?;
    }
    
    // 首先检查字体文件是否存在
    let font_path = Path::new("assets/NotoSansSC-Regular.ttf");
    if !font_path.exists() && !skip_download {
        // 尝试下载字体
        info!("中文字体不存在，尝试下载...");
        let font_resource = DownloadResource {
            name: "NotoSansSC-Regular.ttf".to_string(),
            url: "https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf".to_string(),
            target_path: PathBuf::from("assets/NotoSansSC-Regular.ttf"),
            file_size: Some(8_000_000), // 预估大小
            required: true,
        };
        
        let (status_tx, _) = mpsc::channel();
        let downloader = Downloader::new();
        
        match downloader.download_file(&font_resource, status_tx).await {
            Ok(_) => info!("字体下载成功"),
            Err(e) => {
                warn!("字体下载失败: {}，尝试使用备用链接", e);
                
                // 尝试使用备用链接
                let fallback_resource = DownloadResource {
                    name: "NotoSansSC-Regular.ttf".to_string(),
                    url: "https://cdn.jsdelivr.net/gh/googlefonts/noto-cjk@main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf".to_string(),
                    target_path: PathBuf::from("assets/NotoSansSC-Regular.ttf"),
                    file_size: Some(8_000_000), // 预估大小
                    required: true,
                };
                
                let (status_tx, _) = mpsc::channel();
                match downloader.download_file(&fallback_resource, status_tx).await {
                    Ok(_) => info!("使用备用链接字体下载成功"),
                    Err(e) => warn!("字体下载均失败: {}，UI可能显示为乱码", e),
                }
            },
        }
    }
    
    // 检查指定的模型文件是否存在
    let model_file = Path::new(&model_path);
    if !Downloader::check_file_exists(model_file) && !skip_download {
        info!("模型文件不存在: {}", model_path);
        // 不自动下载，让用户选择
    }
    
    let options = eframe::NativeOptions {
        initial_window_size: Some(Vec2::new(800.0, 600.0)),
        min_window_size: Some(Vec2::new(400.0, 300.0)),
        resizable: true,
        ..Default::default()
    };
    
    let model_path_clone = model_path.clone();
    let device_name_clone = device_name.clone();
    let skip_download_clone = skip_download;
    
    eframe::run_native(
        "AutoTalk - 实时语音转文字",
        options,
        Box::new(move |ctx| {
            configure_ui(ctx);
            Box::new(AutoTalkApp::new(model_path_clone, device_name_clone, skip_download_clone))
        }),
    )
    .map_err(|e| anyhow::anyhow!("运行UI失败: {}", e))?;
    
    Ok(())
} 