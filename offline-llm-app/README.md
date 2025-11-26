# Offline LLM App

A cross-platform offline LLM chat application built with Python, Flet, and llama-cpp-python. This app allows you to run GGUF models locally on your device without an internet connection.

## Features
- **Offline Inference:** Runs entirely on your device.
- **Cross-Platform:** Works on Linux, Windows, and macOS.
- **GGUF Support:** Compatible with GGUF model format (e.g., Llama 3, Mistral).
- **Simple UI:** Clean chat interface.

## Prerequisites

- Python 3.10 or higher
- Git

## Installation & Running (Development)

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/Aadhityan-A/offline-llm.git
    cd offline-llm/offline-llm-app
    ```

2.  **Install dependencies:**
    ```bash
    pip install -r requirements.txt
    ```

3.  **Download a Model:**
    Download a GGUF model (e.g., `llama-2-7b-chat.Q4_K_M.gguf`) from Hugging Face and place it in a known directory.
    Update the `model_path` in `main.py` or use the UI to select it (if implemented).
    *Default configured path:* `/home/aadhityan/Downloads/llama32-1b-qlora-exam_q4_k_m.gguf`

4.  **Run the App:**
    ```bash
    python main.py
    ```

## Building Executables

We use `pyinstaller` (via `flet pack`) to create standalone executables.

### Linux
```bash
pip install pyinstaller
flet pack main.py --name offline-llm-linux
# Executable will be in dist/offline-llm-linux
```

### Windows
```powershell
pip install pyinstaller
flet pack main.py --name offline-llm-windows
# Executable will be in dist/offline-llm-windows.exe
```

### macOS
```bash
pip install pyinstaller
flet pack main.py --name offline-llm-mac
# Executable will be in dist/offline-llm-mac.app
```

## Android Instructions

Running Python apps with C-extensions (like `llama-cpp-python`) as standalone APKs is complex. The recommended way to run this on Android is using **Termux**.

1.  **Install Termux** from F-Droid.
2.  **Update packages:** `pkg update && pkg upgrade`
3.  **Install dependencies:**
    ```bash
    pkg install python git cmake clang
    ```
4.  **Clone and Install:**
    ```bash
    git clone https://github.com/Aadhityan-A/offline-llm.git
    cd offline-llm/offline-llm-app
    pip install flet llama-cpp-python
    ```
    *Note: `llama-cpp-python` compilation on Termux might take some time.*
5.  **Run:**
    ```bash
    python main.py
    ```
    (Flet will open in a browser view or the Flet app if installed).

## CI/CD

This repository includes a GitHub Actions workflow (`.github/workflows/build.yml`) that automatically builds executables for Linux, Windows, and macOS on every push to the `main` branch. The artifacts are uploaded to the GitHub Actions run summary.
