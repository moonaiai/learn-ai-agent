# 随心记

随心记是一个 macOS 原生 Swift 笔记应用，使用无标题栏浮窗，可通过 `Cmd+Enter` 唤起，支持富文本、表格和图片粘贴。

## 构建和安装

```bash
cd notes/suixinji-native
./scripts/install-native.sh
```

脚本会构建并安装 `/Applications/随心记.app`。安装后在任意应用中按 `Cmd+Enter` 唤起窗口，按 `Esc` 隐藏窗口。

## 数据位置

- 开发构建：仓库根目录下的 `notes/.notes/`
- 安装版本：`~/Library/Application Support/com.suixinji.app/.notes/`
- 可用环境变量 `SUIXINJI_NOTES_DIR` 覆盖数据目录

笔记正文使用 RTFD 保存，图片作为富文本附件保存，不依赖 Tauri、Node.js 或 Rust。

## 目录结构

```text
notes/
├── .notes/                         # 本地笔记数据
└── suixinji-native/
    ├── Sources/Suixinji/           # Swift 原生实现
    ├── Package.swift
    ├── build.sh
    └── scripts/install-native.sh
```
