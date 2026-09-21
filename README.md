# EarPose

**English** | [中文](README.zh-CN.md)

Control your Mac by turning your head. Wear AirPods (or other motion-capable headphones), then move the mouse pointer or send arrow keys to play games. No camera. Motion data stays on your Mac.

EarPose lives in the menu bar. It does not show a Dock icon.

[Download EarPose.dmg](https://github.com/Zhang-BigSmart/EarPose/releases/download/v0.0.1/EarPose.dmg)

## What you need

- A Mac running **macOS 14** or later (Intel and Apple Silicon)
- Headphones that support head tracking, set as the Mac’s sound output. Tried with **AirPods Pro (1st generation)** and **AirPods 4 with ANC**
- Two system permissions: **Motion & Fitness** and **Accessibility**

## Install

1. Download **[EarPose.dmg](https://github.com/Zhang-BigSmart/EarPose/releases/download/v0.0.1/EarPose.dmg)** and open it.
2. Drag **EarPose** into **Applications**.
3. Open the **Applications** folder. **Do not double-click.** Control-click (or right-click) **EarPose** → **Open** → **Open** again in the dialog.

macOS may say the developer cannot be verified. That is expected: this build is not notarized by Apple. Allow **only this app**. Do not turn on “Allow apps from anywhere” or disable Gatekeeper for your whole Mac.

If macOS still blocks it: **System Settings → Privacy & Security**, scroll to Security, then click **Open Anyway**.

4. **System Settings → Privacy & Security → Accessibility** → turn on **EarPose**. It must be `/Applications/EarPose.app`.
5. Put on your headphones and set them as the Mac’s audio output. Click the EarPose icon in the menu bar → **Start**. Allow **Motion & Fitness** when asked.

After installing a new version, if the menu says Accessibility is off even though the switch is on, turn the EarPose switch off and on again.

## How to use

Click the EarPose icon in the top-right menu bar (there is no Dock icon).

1. Wear compatible headphones
2. Choose a control mode: **Pointer** or **Arrow keys**
3. Click **Start**
4. Face the screen. Use **Recenter** if the cursor feels off-center
5. **Pause** stops head control but keeps the app running. **Quit** exits

| Shortcut | Action |
| --- | --- |
| Control-Option-Command-H | Start / stop |
| Control-Option-Command-R | Recenter |
| Control-Option-Command-P | Pause |

For games, click the game window first so arrow keys go there.

### Pointer (laser)

- Look around: the pointer follows on the main display
- Short nod: left click
- Look down at the keyboard for a moment: head control pauses, then resumes when you look up
- Using a mouse or trackpad: head control yields for about one second
- Sensitivity slider: smaller angle = more sensitive

### Arrow keys (games)

- A quick turn past the threshold sends one arrow key. Holding still does not repeat it
- After each key, pause in the center briefly before the next flick
- This mode does **not** move the pointer. Use your mouse as usual
- Nod is not a key. Start a web game with the space bar by hand
- Try [Google Snake](https://www.google.com/fbx?fbx=snake_arcade): Arrow keys mode → Start → Recenter → click the game → space to begin → turn your head to steer

Head tracking over Bluetooth has a little lag. Casual games work better than frame-perfect ones.

This is not macOS’s built-in Head Pointer. That feature uses the camera. EarPose reads the sensors in your headphones, so it works in the dark and does not use the camera.

## Troubleshooting

**No icon in the menu bar**  
It may be hidden behind `»`. Or open **Applications** and launch EarPose again.

**The menu says Accessibility is off, but the switch is on**  
The toggle may point at an old copy. Keep only `/Applications/EarPose.app`, then turn the switch off and on.

**Start shows disconnected**  
Connect the headphones, set them as audio output, and wear them. Some Macs (especially some Intel models) cannot read headphone motion. If that happens, the app should stay in disconnected instead of crashing.

**Head control fights the mouse**  
In pointer mode, moving the mouse pauses head control for a moment. In arrow-key mode the pointer is left alone.

**Safety**  
EarPose sends real mouse clicks and keyboard keys. Use Pause if anything goes wrong. Do not leave it running while you type passwords or confirm payments unless you mean to.

## License

Personal project. No open-source license chosen yet.
