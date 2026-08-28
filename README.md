# FlowTranslate

FlowTranslate 是一款原生 macOS 翻译与 AI 文本处理工具，面向输入翻译、全局划词、截图 OCR、润色、总结和跨语写作场景。

## 主要功能

- 输入翻译、划词翻译和截图翻译
- 跨语写作并在原 App 中替换选中文字
- 翻译、润色、跨语写作和总结模式
- DeepL，以及 OpenAI、Gemini、DeepSeek、Groq、OpenRouter、Ollama 和自定义兼容服务
- 简体中文、繁体中文、英语、日语和韩语截图 OCR
- 可配置全局快捷键
- 本地语音朗读、复制和翻译历史
- API Key 保存在 macOS 钥匙串

## 系统要求

- macOS 14 或更高版本
- Apple Silicon Mac
- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 构建

```bash
xcodegen generate
xcodebuild \
  -project FlowTranslate.xcodeproj \
  -scheme FlowTranslate \
  -configuration Debug \
  -derivedDataPath /tmp/FlowTranslateDebug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

运行划词翻译与原位替换需要在 macOS 中授予辅助功能权限；截图翻译需要屏幕录制权限。

## 配置与隐私

- API Key 使用 macOS 钥匙串保存，不写入项目文件。
- 翻译文本只发送到用户自行配置的翻译服务。
- 截图 OCR 使用 Apple Vision 在本机完成。

## 开发记录

详见 [FlowTranslate开发记录.md](./FlowTranslate开发记录.md)。

## 发布文件

安装包将通过 GitHub Releases 发布，不提交到 Git 历史。

## 许可证

本项目采用 [MIT License](./LICENSE)。
