# 🎵 My Open Source Music Player

A Flutter-based music player built with cross-platform support for Linux, Windows, and macOS.

---

## 🚀 Getting Started

### Prerequisites

Before running the application, install the Flutter SDK:

* Follow the official Flutter installation guide: https://docs.flutter.dev/get-started/install

Verify your installation:

```bash
flutter doctor
```

---

## 📥 Clone the Repository

```bash
git clone https://github.com/BaldyMcBaldy/Stuff.git
cd Stuff
```

---

## 📦 Install Dependencies

```bash
flutter pub get
```

---

## 🛠 Platform-Specific Setup

### Linux

Install the required development tools and libraries for your distribution.

#### Fedora

```bash
sudo dnf groupinstall "Development Tools"
sudo dnf install clang cmake ninja-build gtk3-devel
```

#### Ubuntu / Debian / Linux Mint / Pop!_OS

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev
```

#### Arch Linux

```bash
sudo pacman -S base-devel clang cmake ninja gtk3
```

---

### Windows

1. Install **Visual Studio** (not VS Code).

2. During installation, select:

   * **Desktop development with C++**

3. Ensure the following component is installed:

   * **MSVC v14x – VS 2022 C++ x64/x86 Build Tools**

---

### macOS

1. Install **Xcode** from the App Store.
2. Run the following commands:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

---

## ▶️ Running the Application

### Linux

```bash
flutter run -d linux
```

### Windows

```bash
flutter run -d windows
```

### macOS

```bash
flutter run -d macos
```

---

## 🤝 Contributing

Contributions, bug reports, and feature requests are welcome. Feel free to open an issue or submit a pull request.
