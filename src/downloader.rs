use anyhow::{Context, Result};
use futures_util::StreamExt;
use indicatif::{ProgressBar, ProgressStyle};
use log::info;
use reqwest::Client;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use tokio::io::AsyncWriteExt;

// 模型和字体的下载信息
#[derive(Clone)]
pub struct DownloadResource {
    pub name: String,
    pub url: String,
    pub target_path: PathBuf,
    pub file_size: Option<u64>,
    pub required: bool,
}

// 下载状态
#[derive(Debug, Clone)]
pub enum DownloadStatus {
    Pending(String),                // 待下载
    Downloading(String, f32),       // 下载中，带进度
    Completed(String, PathBuf),     // 下载完成
    Failed(String, String),         // 下载失败，带错误信息
    Skipped(String),                // 跳过下载（文件已存在）
}

// 下载管理器
pub struct Downloader {
    client: Client,
}

impl Downloader {
    pub fn new() -> Self {
        Self {
            client: Client::new(),
        }
    }

    // 确保目标目录存在
    fn ensure_dir_exists(path: &Path) -> Result<()> {
        if let Some(parent) = path.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent).context("无法创建目录")?;
            }
        }
        Ok(())
    }

    // 检查文件是否存在且有效
    pub fn check_file_exists(path: &Path) -> bool {
        path.exists() && path.is_file() && path.metadata().map(|m| m.len() > 0).unwrap_or(false)
    }

    // 下载单个文件
    pub async fn download_file(
        &self,
        resource: DownloadResource,
        status_tx: mpsc::Sender<DownloadStatus>,
    ) -> Result<PathBuf> {
        let file_name = resource.name.clone();
        let target_path = resource.target_path.clone();

        // 检查文件是否已存在
        if Self::check_file_exists(&target_path) {
            info!("文件已存在: {}", target_path.display());
            status_tx.send(DownloadStatus::Skipped(file_name)).ok();
            return Ok(target_path);
        }

        // 确保目录存在
        Self::ensure_dir_exists(&target_path)?;

        // 开始下载文件
        status_tx
            .send(DownloadStatus::Pending(file_name.clone()))
            .ok();

        // 发送请求获取文件
        let response = self
            .client
            .get(&resource.url)
            .send()
            .await
            .context("请求失败")?;

        // 检查是否成功
        if !response.status().is_success() {
            let error_msg = format!(
                "下载 {} 失败: HTTP 状态码 {}",
                file_name,
                response.status()
            );
            status_tx
                .send(DownloadStatus::Failed(file_name, error_msg.clone()))
                .ok();
            return Err(anyhow::anyhow!(error_msg));
        }

        // 获取文件大小
        let total_size = response
            .content_length()
            .unwrap_or_else(|| resource.file_size.unwrap_or(0));

        // 设置进度条
        let pb = if total_size > 0 {
            let pb = ProgressBar::new(total_size);
            pb.set_style(
                ProgressStyle::default_bar()
                    .template("{msg}\n{bar:40.cyan/blue} {bytes}/{total_bytes} ({eta})")
                    .unwrap()
                    .progress_chars("##-"),
            );
            pb.set_message(format!("下载 {}", file_name));
            Some(pb)
        } else {
            None
        };

        // 创建临时文件
        let temp_path = target_path.with_extension("download");
        let mut file = tokio::fs::File::create(&temp_path)
            .await
            .context("创建临时文件失败")?;

        // 获取响应数据流
        let mut stream = response.bytes_stream();
        let mut downloaded: u64 = 0;

        // 下载文件
        while let Some(chunk_result) = stream.next().await {
            let chunk = chunk_result.context("下载数据块失败")?;
            file.write_all(&chunk).await.context("写入文件失败")?;
            
            // 更新进度
            downloaded += chunk.len() as u64;
            if let Some(pb) = &pb {
                pb.set_position(downloaded);
            }
            
            // 更新下载状态
            if total_size > 0 {
                let progress = downloaded as f32 / total_size as f32;
                status_tx
                    .send(DownloadStatus::Downloading(file_name.clone(), progress))
                    .ok();
            }
        }

        // 关闭文件
        file.flush().await.context("刷新文件缓冲区失败")?;
        drop(file);

        // 完成进度条
        if let Some(pb) = pb {
            pb.finish_with_message(format!("{} 下载完成", file_name));
        }

        // 将临时文件重命名为目标文件
        tokio::fs::rename(&temp_path, &target_path)
            .await
            .context("重命名文件失败")?;

        // 发送完成状态
        status_tx
            .send(DownloadStatus::Completed(
                file_name.clone(),
                target_path.clone(),
            ))
            .ok();

        info!("{} 下载完成: {}", file_name, target_path.display());
        Ok(target_path)
    }
}

// 获取默认下载资源列表
pub fn get_default_resources() -> Vec<DownloadResource> {
    let mut resources = Vec::new();
    
    // 注释掉Whisper模型下载，因为我们使用模拟实现
    /*
    // Whisper模型 - 提供多种大小供选择
    resources.push(DownloadResource {
        name: "ggml-small.bin".to_string(),
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin".to_string(),
        target_path: PathBuf::from("models/ggml-small.bin"),
        file_size: Some(466_781_312), // ~466MB
        required: true,
    });
    
    resources.push(DownloadResource {
        name: "ggml-base.bin".to_string(),
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin".to_string(),
        target_path: PathBuf::from("models/ggml-base.bin"),
        file_size: Some(142_605_824), // ~142MB
        required: false,
    });
    
    resources.push(DownloadResource {
        name: "ggml-tiny.bin".to_string(),
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin".to_string(),
        target_path: PathBuf::from("models/ggml-tiny.bin"),
        file_size: Some(75_855_224), // ~75MB
        required: false,
    });
    */
    
    // 添加一个简单的示例模型文件
    resources.push(DownloadResource {
        name: "demo-model.bin".to_string(),
        url: "https://raw.githubusercontent.com/openai/whisper/main/README.md".to_string(),
        target_path: PathBuf::from("models/demo-model.bin"),
        file_size: Some(10_240), // ~10KB
        required: true,
    });
    
    // 中文字体
    resources.push(DownloadResource {
        name: "NotoSansSC-Regular.ttf".to_string(),
        url: "https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf".to_string(),
        target_path: PathBuf::from("assets/NotoSansSC-Regular.ttf"),
        file_size: Some(8_000_000), // 预估大小
        required: true,
    });
    
    resources
}

// 解析资源名称，获取显示名称
pub fn get_resource_display_name(name: &str) -> String {
    match name {
        "ggml-small.bin" => "Whisper 小型模型 (较准确, 较慢)".to_string(),
        "ggml-base.bin" => "Whisper 中型模型 (平衡)".to_string(),
        "ggml-tiny.bin" => "Whisper 微型模型 (快速, 较不准确)".to_string(),
        "demo-model.bin" => "演示模型 (仅用于测试)".to_string(),
        "NotoSansSC-Regular.ttf" => "中文字体".to_string(),
        _ => name.to_string(),
    }
} 