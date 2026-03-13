I didn't write nor did I read a single line of what Claude did here.

Have fun.

## Demo

![GutchinTouchTool Demo](assets/demo.gif)

## Install

1. Download `GutchinTouchTool.dmg` from [Releases](https://github.com/nowtilous/GutchinTouchTool/releases)
2. Open the DMG and drag `GutchinTouchTool.app` to Applications
3. Run this in Terminal to bypass Gatekeeper (the app is not notarized):
   ```
   xattr -cr /Applications/GutchinTouchTool.app
   ```
4. Open the app

## Building from source

1. Clone the repo
2. Open `GutchinTouchTool.xcodeproj` in Xcode
3. Build and run (Cmd+R)

The app requires:
- **macOS 13+**
- **Accessibility permissions** — the app will prompt on first launch. Grant access in System Settings > Privacy & Security > Accessibility
- **Automation permissions** — needed for AppleScript-based actions (System Events)

The app uses the private `MultitouchSupport.framework` for raw trackpad touch data. No external dependencies.
