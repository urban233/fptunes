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

> [!IMPORTANT]
> **FFmpeg is required.** To use any conversion or normalization features, you must have `ffmpeg` (and `ffprobe`) installed and available in your system's PATH.

Whether you need to batch convert `.m4a` to 24-bit `.flac` or apply precise EBU R128 two-pass loudness normalization, `fptunes` handles it instantly.

## ✨ Features

- **Studio-Grade Normalization:** True two-pass EBU R128 loudness normalization (target: -14 LUFS) that preserves dynamic range without pumping or clipping.
- **Smart Conversion:** Automatically detects source bit-depth to prevent file bloat (e.g., mapping 32-bit floats to 24-bit FLACs).
- **Native & Portable:** A single, lightweight executable. No Python environments, no Node modules, no `.NET` runtimes required.
- **Cross-Platform:** Write once, compile anywhere. Runs natively on Windows, macOS, and Linux.

---

## 🚀 Installation

### Option 1: Pre-compiled Binaries
**Coming Soon!** Pre-built standalone binaries for Windows, macOS, and Linux are currently in development and will be available in the [Releases](../../releases) section shortly.

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

-----

## 📖 Usage

`fptunes` is built around an automated **Library Management Pipeline** that can intelligently convert, back up, and route your files into a clean directory structure.

### 🚀 Automated Library Management (Recommended)

The `manage` command scans your input directory and creates a multi-step "Action Plan" for every file. It supports recursive subfolder scanning and preserves your directory structure.

**Primary Workflow (Convert, Backup & Route):**
```bash
# Convert M4As to FLAC (preserving original loudness), back up originals, and route to library
fptunes manage --convert --true-peak --move
```

**Options for `manage`:**
- `--convert`: Convert `.m4a` files to FLAC using your INI settings.
- `--true-peak`: **(Highly Recommended)** Bypasses LUFS normalization; uses a True-Peak limiter to preserve the original master's loudness while preventing digital clipping.
- `--move`: Analyzes file quality (bit-depth) and routes files to specific folders (Hi-Res, CD-Quality, etc.).
- `--lufs <val>`: Override the target loudness (default: -14.0).
- `-i, --input <path>`: Temporarily override the input directory.
- `--backup <path>`: Temporarily override the M4A backup directory.

*Note: All management tasks run in **Dry-Run mode** first, showing you the exact pipeline for every file before asking for confirmation.*

### 🔊 Manual Loudness Normalization

Apply two-pass EBU R128 normalization to a single audio file:

```bash
fptunes norm -i input.m4a --two-pass
```

### 🛠️ General Help

View all available commands and options:

```bash
fptunes --help
```

-----

## ⚙️ Configuration

`fptunes` uses an INI configuration file (`fptunes.ini`) located in the same directory as the executable. Generate a fresh template with:

```bash
fptunes config --regenerate
```

### Key Configuration Sections

**`[Conversion]`**
- `TargetLUFS`: The integrated loudness target (e.g., -14.0).
- `SampleFormat`: The bit-depth for FLAC (use `s32` for 24-bit).
- `FFMpegPath`: Path to your ffmpeg binary.

**`[Management]`**
- `InputPath`: Where the tool looks for new music files.
- `HiResPath`: Destination for 24-bit/32-bit FLAC/ALAC.
- `CDQualityPath`: Destination for 16-bit FLAC/ALAC.
- `WavPath` / `Mp3Path`: Destinations for other formats.
- `BackupM4APath`: Where original `.m4a` files are moved after conversion.

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
