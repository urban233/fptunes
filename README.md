<p align="center">
  <img src="assets/fptunes-logo.png" alt="fptunes Logo" width="250">
</p>

<p align="center">
  <strong>A blazingly fast, cross-platform CLI audio suite written in Free Pascal.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/FPC-3.2.2-purple.svg?style=flat-square" alt="Free Pascal Compiler">
  <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg?style=flat-square" alt="Cross Platform">
  <img src="https://img.shields.io/badge/License-BSD--3--Clause-blue.svg?style=flat-square" alt="License">
</p>

---

## 🎵 Overview

**`fptunes`** is a native, zero-dependency command-line utility for managing, converting, and normalizing your audio library. Built on top of the robust Free Pascal Compiler (FPC) and utilizing `ffmpeg` under the hood, it delivers studio-grade audio processing without the bloat of heavy runtime environments.

Whether you need to batch convert `.m4a` to 24-bit `.flac` or apply precise EBU R128 two-pass loudness normalization, `fptunes` handles it instantly.

## ✨ Features

- **Studio-Grade Normalization:** True two-pass EBU R128 loudness normalization (target: -14 LUFS) that preserves dynamic range without pumping or clipping.
- **Smart Conversion:** Automatically detects source bit-depth to prevent file bloat (e.g., mapping 32-bit floats to 24-bit FLACs).
- **Native & Portable:** A single, lightweight executable. No Python environments, no Node modules, no `.NET` runtimes required.
- **Cross-Platform:** Write once, compile anywhere. Runs natively on Windows, macOS, and Linux.

---

## 🚀 Installation

*Note: `fptunes` requires `ffmpeg` to be installed and available on your system's PATH.*

### Option 1: Pre-compiled Binaries
Download the latest standalone executable for your operating system from the [Releases](../../releases) page. Put it in your system's `PATH` and you're good to go.

### Option 2: Build from Source
Building `fptunes` is incredibly straightforward. The project uses a custom compiler configuration (`fptunes.cfg`) to ensure a pristine source tree, outputting all build artifacts safely to `bin/` and `obj/` folders.

Ensure you have the [Free Pascal Compiler](https://www.freepascal.org/) installed, then clone the repository:

```bash
git clone https://github.com/urban233/fptunes.git
cd fptunes
````

**For Windows:**
Use the included batch script to compile the project.

```powershell
.\build.bat
```

*The compiled executable will be located at `bin\fptunes.exe`.*

**For macOS / Linux:**
Use the included Makefile to compile and optionally install the project system-wide.

```bash
# Build the executable (outputs to bin/fptunes)
make

# Install globally to /usr/local/bin (requires sudo)
sudo make install
```

*(To clean your build environment on any OS, run `.\build.bat clean` or `make clean`).*

-----

## 📖 Usage

`fptunes` uses a modern subcommand structure to route your tasks.

### Loudness Normalization

Apply two-pass EBU R128 normalization to an audio file:

```bash
fptunes norm input.m4a --two-pass
```

### Format Conversion

Convert a file to the most efficient FLAC format based on its original bit depth:

```bash
fptunes convert input.m4a --format flac
```

### General Help

View all available commands and options:

```bash
fptunes --help
```

-----

## 🛠️ Architecture

`fptunes` is built using modern Object Pascal conventions and a professional build pipeline:

  * **`TCustomApplication`**: Handles CLI routing, parameter parsing, and help flag generation natively.
  * **`TProcess`**: Safely wraps and executes asynchronous `ffmpeg` calls with custom pipe-reading to prevent OS deadlocks.
  * **`fpjson`**: Natively parses complex JSON analysis data generated during two-pass normalization.
  * **`fptunes.cfg`**: A custom compiler configuration file that enforces strict `-O3` and `-XX` (Smart Linking) optimizations, stripping debug symbols (`-Xs`) to generate the smallest, fastest binary possible.

-----

## 🤝 Contributing

Contributions, issues, and feature requests are welcome\!
Feel free to check out the [issues page](https://www.google.com/search?q=../../issues). If you want to add new audio filters or management subcommands, please ensure your code follows the existing unit structure.

## 📄 License

This project is licensed under the BSD-3-Clause License - see the [LICENSE](LICENSE) file for details.

-----

<p align="center"\>
<i\>Built with ❤️ and Free Pascal.</i\>
</p\>
