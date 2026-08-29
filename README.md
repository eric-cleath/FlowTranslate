# PallasOwl

PallasOwl（原 FlowTranslate）是一款原生 macOS 翻译与 AI 文本处理工具，面向输入翻译、全局划词、截图 OCR、润色、总结和跨语写作场景。

## 主要功能

- 输入翻译、划词翻译和截图翻译
- 跨语写作并在原 App 中替换选中文字
- 翻译、润色、跨语写作和总结模式
- DeepL，以及 OpenAI、Gemini、DeepSeek、Groq、OpenRouter、Ollama 和自定义兼容服务
- 简体中文、繁体中文、英语、日语和韩语截图 OCR
- 可配置全局快捷键
- 本地语音朗读、复制和翻译历史
- API Key 保存在 macOS 钥匙串
- Bob 风格的 `+ / −` 引擎管理及每个引擎独立验证
- AI 文本处理可独立配置引擎，也可与文本翻译共用引擎
- 简体中文、英语、法语和日语界面
- 文档翻译支持 PDF、Word、TXT、Markdown 与常见图片
- 文本 PDF 直接提取，扫描 PDF 与图片使用本地 OCR
- 长文档自动分段、处理进度、暂停与 Markdown/TXT 导出
- 文档翻译可共用文本引擎，或单独配置 AI / DeepL
- 支持从剪贴板直接粘贴图片（⌘V）并 OCR 翻译

## 系统要求

- macOS 14 或更高版本
- Apple Silicon Mac
- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 构建

```bash
xcodegen generate
xcodebuild \
  -project PallasOwl.xcodeproj \
  -scheme PallasOwl \
  -configuration Debug \
  -derivedDataPath /tmp/PallasOwlDebug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

运行划词翻译与原位替换需要在 macOS 中授予辅助功能权限；截图翻译需要屏幕录制权限。

## 配置与隐私

- API Key 使用 macOS 钥匙串保存，不写入项目文件。
- 翻译文本只发送到用户自行配置的翻译服务。
- 截图 OCR 使用 Apple Vision 在本机完成。

## 开发记录

详见 [FlowTranslate开发记录.md](./FlowTranslate开发记录.md)。该文件保留原名，以便 Obsidian 链接和既有记录继续有效。

## 发布文件

安装包将通过 GitHub Releases 发布，不提交到 Git 历史。

## 许可证

本项目采用 [MIT License](./LICENSE)。
