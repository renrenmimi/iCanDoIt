# iCanDoIt ✅

A tiny, pretty daily planner for macOS — write down what you want to get done today, attach a little reward to each task, and celebrate when you finish everything.

一个小而美的 macOS 每日计划 App:每天写下想完成的事,给每件事绑一个"完成后的小奖励",全部做完时收获彩带与领奖仪式。

## Features

- 🌅 **Morning ritual** — every day starts with one question: *What do you want to get done today?*
- 🎁 **Reward yourself** — attach an optional reward to each task ("an iced americano", "one episode of my show"…)
- 🏆 **Perfect Day** — finish everything and get a confetti celebration listing all the rewards you've earned
- 🔥 **Streaks & stats** — current/best streak, total done, perfect days
- 🗺 **Consistency map** — a GitHub-style heatmap of your last 6 months, with instant custom hover tooltips
- 🪟 **Glass everything** — real behind-window frosted glass, drifting aurora glow, springy Apple-flavored animations, trackpad haptics
- 💾 **Local-first** — data lives in a local SwiftData (SQLite) store; no network, no accounts

## Screenshots

| Today | Review |
|---|---|
| ![Tasks](docs/tasks.png) | ![Review](docs/review.png) |

![Perfect Day](docs/celebration.png)

## Build & install

Requires Xcode (tested with Xcode 26 / Swift 6.3, macOS 15+).

```bash
./build.sh                      # builds and packages build/iCanDoIt.app
cp -R build/iCanDoIt.app /Applications/
```

No Xcode project needed — it's a plain Swift Package (SwiftUI + SwiftData) with a small packaging script.

### Dev snapshot mode

The binary has a hidden self-check flag that renders every screen to PNGs off-screen (used to verify visuals without screen-recording permissions):

```bash
.build/debug/iCanDoIt --snapshot /tmp/snaps
```

## Tech notes

- **SwiftUI + SwiftData**, zero third-party dependencies
- Frosted glass via `NSVisualEffectView` (`.fullScreenUI`, behind-window) with a thin tint so the desktop shows through
- Confetti is a pure-SwiftUI `Canvas` particle system
- The heatmap flattens its 182 shadowed cells into one GPU texture (`drawingGroup`) so screen transitions stay buttery
- Icon is generated programmatically by `scripts/make_icon.swift`

---

Built with [Claude Code](https://claude.com/claude-code) 🤖
