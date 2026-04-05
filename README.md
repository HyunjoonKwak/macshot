# ScreenShot

<p align="center">
  <img src="assets/logo.svg" alt="ScreenShot logo" width="200"/>
</p>

<p align="center">
  <b>Free, open-source screenshot & screen recording tool for macOS.</b><br>
  Native Swift + AppKit. No Electron. No bloat.<br>
  Forked from <a href="https://github.com/sw33tLie/macshot">macshot</a> by sw33tLie.
</p>

## What's New (vs. original macshot)

This fork adds **40 new features and improvements**:

### Capture
- Capture region presets (save/load named regions)
- Fixed aspect ratio on Shift+drag (1:1, 4:3, 16:9, 3:2)
- Recapture last area with global hotkey
- Quick save without dialog

### Annotation Editing
- Duplicate (Cmd+D), Lock/Unlock (Cmd+L)
- Multi-select (Shift+click) with batch move/delete
- Arrow key nudge (1px, Shift=10px)
- Z-order change (Cmd+]/[)
- Alignment tools (Cmd+Shift+arrows)
- Per-annotation opacity (Cmd+Opt+scroll)
- Style copy/paste (Cmd+Shift+C/V)
- Style presets (save/apply via context menu)
- Right-click context menu on annotations

### Image Processing
- Auto drop shadow
- Custom text watermark with opacity
- Capture timestamp overlay
- EXIF metadata auto-strip
- Max dimension auto-resize
- Auto-save file on clipboard copy

### Integration & Automation
- Shortcuts.app (3 App Intents)
- URL Scheme (`screenshot://capture`, `screenshot://ocr`, etc.)
- Finder Services menu (Open in ScreenShot)
- macOS Notification Center
- Clipboard image watch mode

### UX
- Korean localization (46 strings)
- Keyboard shortcut help overlay (press `?`)
- Tool shortcut customization (Preferences UI)
- Pin window opacity (Opt+scroll)
- Editor Always on Top toggle
- Image 90 degree rotation (CW/CCW)
- Recording encoding progress HUD
- Webhook uploader (custom HTTP POST)

## Build & Run

1. Clone:
   ```bash
   git clone https://github.com/HyunjoonKwak/macshot.git
   cd macshot
   ```

2. Open `macshot.xcodeproj` in Xcode

3. Build & Run (Cmd+R)

4. Grant Screen Recording permission when prompted

5. App appears as **ScreenShot** in menu bar

## Default Hotkeys

| Shortcut | Action |
|---|---|
| Cmd+Shift+X | Capture Area |
| Cmd+Shift+F | Capture Full Screen |
| Cmd+Shift+R | Record Area |
| Cmd+Shift+H | History |
| Cmd+Shift+T | OCR Capture |
| Cmd+Shift+S | Quick Capture |

## URL Scheme

```
open screenshot://capture
open screenshot://fullscreen
open screenshot://ocr
open screenshot://quick
open screenshot://record
open screenshot://recapture
open screenshot://history
open screenshot://settings
```

## Keyboard Shortcuts (in overlay)

Press `?` in the capture overlay to see all available shortcuts.

| Key | Action |
|---|---|
| Cmd+D | Duplicate annotation |
| Cmd+L | Lock/Unlock annotation |
| Cmd+]/[ | Bring forward / Send backward |
| Cmd+Shift+C/V | Copy/Paste annotation style |
| Cmd+Shift+Arrows | Align to edges |
| Cmd+Arrows | Center align |
| Arrow keys | Nudge 1px (Shift=10px) |
| Cmd+Opt+Scroll | Annotation opacity |
| Shift+Click | Multi-select |
| Cmd+A then Del | Delete all annotations |

## License

GPLv3 - see [LICENSE](LICENSE)

Based on [macshot](https://github.com/sw33tLie/macshot) by sw33tLie.
