use clap::Parser;
use env_logger;
use log::{info, LevelFilter};
use std::thread;
use std::time::Duration;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// 演示模式类型 (1: 单次, 2: 连续)
    #[arg(short, long, default_value = "1")]
    mode: u8,
}

fn setup_logger() {
    let mut builder = env_logger::Builder::new();
    builder.filter_level(LevelFilter::Info).init();
}

fn main() {
    setup_logger();
    let args = Args::parse();
    
    info!("启动AutoTalk演示程序...");
    info!("本演示程序仅展示语音转文字的基本流程，不涉及实际的语音处理");
    
    match args.mode {
        1 => run_single_mode(),
        2 => run_continuous_mode(),
        _ => {
            info!("未知的演示模式，使用单次模式");
            run_single_mode();
        }
    }
    
    info!("演示结束");
}

fn run_single_mode() {
    info!("运行单次演示模式");
    
    info!("步骤1: 加载模拟语音模型...");
    thread::sleep(Duration::from_secs(1));
    info!("模型加载完成!");
    
    info!("步骤2: 初始化音频捕获设备...");
    thread::sleep(Duration::from_millis(500));
    info!("音频设备就绪!");
    
    info!("步骤3: 捕获音频数据...");
    thread::sleep(Duration::from_secs(2));
    info!("已捕获5秒音频数据!");
    
    info!("步骤4: 处理音频并转换为文字...");
    thread::sleep(Duration::from_secs(1));
    
    info!("转写结果: \"这是一个演示程序，展示了语音转文字的基本流程。\"");
}

fn run_continuous_mode() {
    info!("运行连续演示模式");
    
    info!("步骤1: 加载模拟语音模型...");
    thread::sleep(Duration::from_secs(1));
    info!("模型加载完成!");
    
    info!("步骤2: 初始化音频捕获设备...");
    thread::sleep(Duration::from_millis(500));
    info!("音频设备就绪!");
    
    info!("步骤3: 开始连续捕获音频数据...");
    
    for i in 1..=5 {
        info!("捕获第 {} 段音频...", i);
        thread::sleep(Duration::from_secs(1));
        
        let message = match i {
            1 => "我想体验语音转文字功能。",
            2 => "AutoTalk是一个很好的演示程序。",
            3 => "实际应用中这里会显示真实的语音识别内容。",
            4 => "语音识别技术正在不断进步。",
            5 => "感谢您的体验，希望您喜欢这个演示。",
            _ => "",
        };
        
        info!("转写结果 {}: \"{}\"", i, message);
    }
    
    info!("演示完成，在真实应用中，这个过程会持续进行直到用户停止。");
} 