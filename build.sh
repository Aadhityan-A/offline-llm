#!/bin/bash

# Build script for Offline LLM
# This script builds llama.cpp and the Flutter app for your platform

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Offline LLM Build Script ==="

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Linux*)     PLATFORM=linux;;
    Darwin*)    PLATFORM=macos;;
    MINGW*|CYGWIN*|MSYS*)    PLATFORM=windows;;
    *)          echo "Unknown OS: $OS"; exit 1;;
esac

echo "Detected platform: $PLATFORM"

# Build llama.cpp if not already built
if [ ! -f "bin/llama-cli" ] && [ ! -f "bin/llama-cli.exe" ]; then
    echo ""
    echo "=== Building llama.cpp ==="
    
    if [ ! -d "llama_cpp_build" ]; then
        git clone --depth 1 https://github.com/ggerganov/llama.cpp.git llama_cpp_build
    fi
    
    cd llama_cpp_build
    cmake -B build -DLLAMA_CURL=OFF
    
    if [ "$PLATFORM" = "linux" ] || [ "$PLATFORM" = "macos" ]; then
        cmake --build build --config Release -j$(nproc 2>/dev/null || sysctl -n hw.ncpu) -- llama-cli
    else
        cmake --build build --config Release --target llama-cli
    fi
    
    cd ..
    mkdir -p bin
    
    if [ "$PLATFORM" = "windows" ]; then
        cp llama_cpp_build/build/bin/Release/llama-cli.exe bin/
        cp llama_cpp_build/build/bin/Release/*.dll bin/ 2>/dev/null || true
    else
        cp llama_cpp_build/build/bin/llama-cli bin/
        cp llama_cpp_build/build/bin/*.so bin/ 2>/dev/null || true
        cp llama_cpp_build/build/bin/*.dylib bin/ 2>/dev/null || true
    fi
    
    echo "llama.cpp built successfully!"
else
    echo "llama.cpp already built, skipping..."
fi

# Get Flutter dependencies
echo ""
echo "=== Getting Flutter dependencies ==="
flutter pub get

# Build Flutter app
echo ""
echo "=== Building Flutter app for $PLATFORM ==="

case "$PLATFORM" in
    linux)
        flutter build linux --release
        mkdir -p build/linux/x64/release/bundle/bin
        cp bin/llama-cli build/linux/x64/release/bundle/bin/
        cp bin/*.so build/linux/x64/release/bundle/lib/ 2>/dev/null || true
        echo ""
        echo "Build complete! Run with:"
        echo "  cd build/linux/x64/release/bundle && ./offline_llm"
        ;;
    macos)
        flutter build macos --release
        mkdir -p build/macos/Build/Products/Release/offline_llm.app/Contents/Resources
        cp bin/* build/macos/Build/Products/Release/offline_llm.app/Contents/Resources/
        echo ""
        echo "Build complete! App located at:"
        echo "  build/macos/Build/Products/Release/offline_llm.app"
        ;;
    windows)
        flutter build windows --release
        cp bin/* build/windows/x64/runner/Release/
        echo ""
        echo "Build complete! Run with:"
        echo "  build\\windows\\x64\\runner\\Release\\offline_llm.exe"
        ;;
esac

echo ""
echo "=== Build completed successfully! ==="
