<p align="center">
  <img src="assets/demo.gif" alt="GutchinTouchTool Demo" width="800">
</p>

<h1 align="center">GutchinTouchTool</h1>

<p align="center">
  <strong>The ultimate macOS trackpad gesture engine.</strong><br>
  Map any multitouch gesture to any action. Swipes, taps, circles, edge slides, drawings — if your fingers can do it, GutchinTouchTool can bind it.
</p>

<p align="center">
  <a href="https://github.com/nowtilous/GutchinTouchTool/releases/latest"><img src="https://img.shields.io/github/v/release/nowtilous/GutchinTouchTool?style=flat-square&color=blueviolet" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/badge/vibe--coded-100%25-ff69b4?style=flat-square" alt="Vibe Coded">
</p>

---

## What is this?

GutchinTouchTool turns your MacBook trackpad into a programmable input surface. Define custom gestures — from simple two-finger swipes to complex multi-finger patterns — and map them to keyboard shortcuts, app launches, scripts, window management, media controls, and more.

**I didn't write nor did I read a single line of what Claude did here. Have fun.**

## Features

- **30+ gesture types** — taps, swipes, circles, edge slides, drawings, TipTaps, pinches, and more
- **Per-app targeting** — bind gestures to specific applications or use them globally
- **Velocity-aware swipes** — configurable per-gesture velocity thresholds to distinguish flicks from scrolls
- **Live touch visualizer** — real-time trackpad touch display with finger tracking
- **Gesture console** — live log of detected gestures for debugging and tuning
- **Menu bar service** — runs silently in the background, toggle on/off from the system tray
- **Auto-updates** — checks GitHub Releases and self-updates with a single click
- **Preset export/import** — share your gesture configs with others
- **Statistics dashboard** — track gesture usage over time
- **Zero dependencies** — built entirely with native frameworks

## Install

1. Download `GutchinTouchTool.dmg` from the [latest release](https://github.com/nowtilous/GutchinTouchTool/releases/latest)
2. Open the DMG and drag `GutchinTouchTool.app` to `/Applications`
3. Bypass Gatekeeper (the app is not notarized):
   ```bash
   xattr -cr /Applications/GutchinTouchTool.app
   ```
4. Launch the app — it lives in your menu bar

## Building from source

```bash
git clone https://github.com/nowtilous/GutchinTouchTool.git
cd GutchinTouchTool
open GutchinTouchTool.xcodeproj
# Build and run (Cmd+R)
```

## Requirements

- **macOS 14+**
- **Accessibility permissions** — the app will prompt on first launch
- **Automation permissions** — needed for AppleScript-based actions

## How it works

GutchinTouchTool uses the private `MultitouchSupport.framework` to read raw trackpad touch data at the hardware level. This gives direct access to individual finger positions, contact sizes, and pressure — bypassing the system gesture recognizer entirely. No external dependencies, no daemons, no kernel extensions.

---

<p align="center">
  <sub>Built with bare hands and mass AI prompting.</sub>
</p>
