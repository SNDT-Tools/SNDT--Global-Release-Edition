<img src="https://github.com/user-attachments/assets/d73ee13a-b0b8-435e-8f59-60b77846364f" width="100%">

# SNDT - Global Release Edition!

![OS](https://img.shields.io/badge/OS-Windows_10_%7C_11-blue?style=for-the-badge&logo=windows)
![License](https://img.shields.io/github/license/SNDT-Tools/SNDT--Global-Release-Edition?style=for-the-badge)
![Release](https://img.shields.io/github/v/release/SNDT-Tools/SNDT--Global-Release-Edition?include_prereleases&style=for-the-badge)
![GitHub Downloads](https://img.shields.io/github/downloads/SNDT-Tools/SNDT--Global-Release-Edition/total?style=for-the-badge&color=ff4b00)

> **A professional, hardware-accelerated, and completely portable network diagnostics tool for Windows.** > Built for system administrators, competitive gamers, and power users to troubleshoot routing, latency, and bufferbloat issues in real-time.

---

## 🚀 The GUI Evolution (v1.1.0)
SNDT has evolved from a pure CLI script into a **fully interactive, custom-built Graphical User Interface (GUI)**. We built a sleek, modern dashboard that processes complex diagnostic data in real-time, transforming raw network metrics into visually intuitive, instantly actionable insights.

### ✨ Key Features
* 🖥️ **Custom Electron Frontend:** A frameless, premium dark-themed aesthetic with custom window controls and ultra-smooth UI transitions.
* 🌀 **Real-Time Visual Feedback:** Dynamic UI animations and state-driven "Phase" morphing. The central UI core changes shape, color, and rotation speed depending on active network load and test progress.
* ⚙️ **Frictionless Setup Flow:** The required Ookla Speedtest CLI download and EULA agreement are seamlessly integrated directly into the application UI. 
* 🔍 **Precision UI Scaling:** A dedicated precision slider allows you to dynamically adjust the interface zoom factor for perfect readability on 1080p, 1440p, and 4K ultra-wide monitors.
* 🗂️ **Categorized Results:** Post-test results are cleanly organized into dedicated tabs (**Overview**, **DNS Benchmark**, and **Traceroute**) to eliminate information overload.
* 💯 **Comprehensive Grading System:** Your network receives an immediate, color-coded letter grade (**A to F**), strictly calculated based on core latency, jitter variance, packet loss, and bufferbloat spikes.

---

## 🔄 Under the Hood
* 🧠 **Advanced Architecture:** The original PowerShell script acts as a silent, invisible "motor" deep in the background, communicating blazingly fast with the Electron frontend via structured JSON parsing and bidirectional IPC streams.
* ⚡ **Ping Engine Rewrite:** Powered by the native `.NET System.Net.NetworkInformation.Ping` class for lightning-fast, highly precise, and resource-efficient latency measurements.
* 🔒 **Hardware Vault:** Anonymous SHA-256 MAC hashing protects your hardware identity.

---

## 💾 Installation & Usage

SNDT is designed to leave no trace on your system. No registry keys, no messy installers.

1. Download the latest `SNDT v1.1.0 -Global Release Edition.zip` from the **[Releases](../../releases)** page.
2. Run the executable.
3. **Diagnose.**

---

### 🔮 Sneak Peek: What's coming in v1.1.5?

* 👁️ **Streamer Mode (Privacy Toggle):** We are currently working on a dedicated "Eye" icon right next to your IP addresses. With a single click, you will be able to **toggle your public IP visibility on or off** (censoring it instantly). This will make it **100% safe to share screenshots or live streams** of your dashboard with the world without leaking your private data!
