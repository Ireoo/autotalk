mod audio;
mod downloader;
mod transcriber;
mod ui;

use anyhow::Result;
use clap::Parser;
use log::{error, info};

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Whisper模型路径
    #[arg(short, long, default_value = "models/demo-model.bin")]
    model_path: String,

    /// 录音设备名称，不指定则使用默认设备
    #[arg(short, long)]
    device: Option<String>,

    /// 跳过检查和下载资源
    #[arg(short, long)]
    skip_download: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    // 初始化日志，设置详细级别
    std::env::set_var("RUST_LOG", "debug,cpal=trace");
    env_logger::init();

    let args = Args::parse();

    info!("启动AutoTalk - 实时语音转文字程序");
    info!("使用模型: {}", args.model_path);

    match ui::run_app(args.model_path, args.device, args.skip_download).await {
        Ok(_) => info!("程序正常退出"),
        Err(e) => error!("程序异常退出: {}", e),
    }

    Ok(())
}
