#  My Open Source Music Player

A cross-platform music player built with Flutter.

---

##  Getting Started

### Prerequisites

Install the Flutter SDK and ensure it is available in your PATH.

Official Flutter installation guide:

https://docs.flutter.dev/get-started/install

Verify your installation:

```bash
flutter doctor
```

---

##  Clone the Repository

```bash
git clone https://github.com/BaldyMcBaldy/Stuff.git
cd Stuff
```

---

##  Install Dependencies

```bash
flutter pub get
```

---

## 🐧 Linux Setup

Flutter desktop applications require additional development libraries depending on your Linux distribution.

### Fedora

Install the dependencies required for Flutter Linux desktop development:

```bash
sudo dnf install clang cmake ninja-build gtk3-devel
```

### Ubuntu

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev
```

### Debian

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev
```

### Linux Mint

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev
```

### Pop!_OS

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev
```

### Arch Linux

```bash
sudo pacman -S base-devel clang cmake ninja gtk3
```

### Verify Linux Desktop Support

After installing the required packages, run:

```bash
flutter doctor
```

Ensure that **Linux toolchain** shows a ✓ before continuing.

---

##  Run the Application

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

## Windows Setup

1. Install Visual Studio (not VS Code).
2. During installation, select **Desktop development with C++**.
3. Ensure the MSVC build tools are installed.
4. Verify the setup:

```bash
flutter doctor
```

---

##  macOS Setup

1. Install Xcode from the App Store.
2. Run:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

3. Verify the setup:

```bash
flutter doctor
```

---

## Contributing

Contributions, bug reports, and feature requests are welcome.


