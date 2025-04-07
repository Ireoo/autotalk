static const std::vector<std::string> non_speech_tokens = {
    "\"", "#", "(", ")", "*", "+", "/", ":", ";", "<", "=", ">", "@", "[", "\\", "]", "^",
    "_", "`", "{", "|", "}", "~", "[", "]", "{", "}", "<<", ">>", "<<<", ">>>", "--",
    "---", "-(", "-[", "('", "(\"", "((", "))", "(((", ")))", "[[", "]]", "{{", "}}", "++",
    "+++", "+", "+", "+", "+", "+", "+", "+"
}; 

WHISPER_ATTRIBUTE_FORMAT(2, 3)
static void whisper_log_internal        (ggml_log_level level, const char * format, ...);
static void whisper_log_callback_default(ggml_log_level level, const char * text, void * user_data);

// 前向声明
struct whisper_global {
    // We save the log callback globally
    ggml_log_callback log_callback = whisper_log_callback_default;
    void * log_callback_user_data = nullptr;
};

// 添加日志函数实现
static void whisper_log_callback_default(ggml_log_level level, const char * text, void * /*user_data*/) {
    (void) level;
#ifndef WHISPER_DEBUG
    if (level == GGML_LOG_LEVEL_DEBUG) {
        return;
    }
#endif
    fputs(text, stderr);
    fflush(stderr);
}

static void whisper_log_internal(ggml_log_level level, const char * format, ...) {
    if (g_state.log_callback == nullptr) {
        return;
    }
    
    va_list args;
    va_start(args, format);
    
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), format, args);
    
    va_end(args);
    
    g_state.log_callback(level, buffer, g_state.log_callback_user_data);
}

#define WHISPER_LOG_ERROR(...) whisper_log_internal(GGML_LOG_LEVEL_ERROR, __VA_ARGS__) 

struct whisper_model {
    std::string path_model; // populated by whisper_init_from_file_with_params()
};

template<typename T>
// ... existing code ... 

static ggml_backend_t whisper_backend_init_gpu(const whisper_context_params & params) {
    // 移除对g_state的引用，直接使用默认回调
    ggml_log_set(whisper_log_callback_default, nullptr);

    if (params.use_gpu) {
// ... existing code ...
} 