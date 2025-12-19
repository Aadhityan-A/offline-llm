# Developer Notes

This document provides detailed instructions for building the Offline LLM application from source on all supported platforms.

## Prerequisites

### All Platforms
- [Flutter SDK](https://flutter.dev/docs/get-started/install) version 3.0 or higher
- [Git](https://git-scm.com/)
- [CMake](https://cmake.org/) version 3.16 or higher

### Linux
```bash
sudo apt-get update
sudo apt-get install -y cmake ninja-build clang libgtk-3-dev
```

### Windows
- [Visual Studio 2022](https://visualstudio.microsoft.com/) with "Desktop development with C++" workload
- Windows 10 SDK

### macOS
- Xcode Command Line Tools
```bash
xcode-select --install
```

### Android
- [Android Studio](https://developer.android.com/studio) with:
  - Android SDK
  - Android NDK (r25c recommended)
  - CMake for Android

## Quick Build (Linux/macOS)

The easiest way to build is using the provided build script:

```bash
git clone https://github.com/Aadhityan-A/offline-llm.git
cd offline-llm
./build.sh
```

## Manual Build Steps

### Step 1: Clone the Repository

```bash
git clone https://github.com/Aadhityan-A/offline-llm.git
cd offline-llm
```

### Step 2: Build llama.cpp

#### Linux / macOS
```bash
git clone --depth 1 https://github.com/ggerganov/llama.cpp.git llama_cpp_build
cd llama_cpp_build
cmake -B build -DLLAMA_CURL=OFF
cmake --build build --config Release -j$(nproc) -- llama-cli
cd ..

mkdir -p bin
cp llama_cpp_build/build/bin/llama-cli bin/
cp llama_cpp_build/build/bin/*.so bin/ 2>/dev/null || true
cp llama_cpp_build/build/bin/*.dylib bin/ 2>/dev/null || true
```

#### Windows (PowerShell)
```powershell
git clone --depth 1 https://github.com/ggerganov/llama.cpp.git llama_cpp_build
cd llama_cpp_build
cmake -B build -DLLAMA_CURL=OFF
cmake --build build --config Release --target llama-cli
cd ..

New-Item -ItemType Directory -Force -Path bin
Copy-Item llama_cpp_build/build/bin/Release/llama-cli.exe bin/
Copy-Item llama_cpp_build/build/bin/Release/*.dll bin/ -ErrorAction SilentlyContinue
```

### Step 3: Get Flutter Dependencies

```bash
flutter pub get
```

### Step 4: Build for Your Platform

#### Linux
```bash
flutter build linux --release
cp bin/* build/linux/x64/release/bundle/lib/
```

The built application will be in `build/linux/x64/release/bundle/`.

To run:
```bash
cd build/linux/x64/release/bundle
LD_LIBRARY_PATH=./lib:$LD_LIBRARY_PATH ./offline_llm
```

#### Windows
```powershell
flutter build windows --release
Copy-Item bin\* build\windows\x64\runner\Release\
```

The built application will be in `build\windows\x64\runner\Release\`.

#### macOS
```bash
flutter build macos --release
mkdir -p build/macos/Build/Products/Release/offline_llm.app/Contents/Resources
cp bin/* build/macos/Build/Products/Release/offline_llm.app/Contents/Resources/
```

The built application will be at `build/macos/Build/Products/Release/offline_llm.app`.

#### Android

Building for Android requires additional setup for cross-compiling llama.cpp:

1. **Set up Android NDK**
```bash
export ANDROID_NDK_HOME=/path/to/android-ndk
```

2. **Build llama.cpp for Android**
```bash
cd llama_cpp_build
mkdir -p build-android-arm64
cd build-android-arm64
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DLLAMA_CURL=OFF \
  -DGGML_OPENMP=OFF
cmake --build . --config Release -j$(nproc) -- llama-cli
cd ../..

# Copy to Android JNI directory
mkdir -p android/app/src/main/jniLibs/arm64-v8a
cp llama_cpp_build/build-android-arm64/bin/llama-cli android/app/src/main/jniLibs/arm64-v8a/
cp llama_cpp_build/build-android-arm64/bin/*.so android/app/src/main/jniLibs/arm64-v8a/
```

3. **Build APK**
```bash
flutter build apk --release
```

The APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

## Troubleshooting

### Linux: "llama-cli not found"
Make sure the llama-cli binary is in the `lib/` folder of the app bundle:
```bash
cp bin/* build/linux/x64/release/bundle/lib/
```

### Linux: Shared library errors
Set the library path:
```bash
export LD_LIBRARY_PATH=/path/to/app/lib:$LD_LIBRARY_PATH
```

### Windows: Missing DLLs
Ensure all .dll files from llama.cpp build are copied to the Release folder.

### macOS: App won't open
You may need to remove the quarantine attribute:
```bash
xattr -r -d com.apple.quarantine offline_llm.app
```

### Android: Native library not found
- Ensure you're building for the correct architecture (arm64-v8a for most modern devices)
- Verify JNI libraries are in the correct path

## CI/CD

The project includes GitHub Actions workflows that automatically build for all platforms when:
- A pull request is opened against `main`
- A push is made to `main`
- A version tag (e.g., `v1.0.0`) is created

Pre-built binaries for all platforms are available in the [Releases](https://github.com/Aadhityan-A/offline-llm/releases) section.

## Creating a Release

To create a new release:

```bash
git tag -a v1.x.x -m "Release description"
git push origin v1.x.x
```

This will trigger the CI/CD pipeline to build and publish release artifacts for all platforms.
