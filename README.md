# EyeRest

EyeRest is a small, native macOS menu-bar app that reminds you to rest your eyes using the
**20-20-20 rule**: every 20 minutes, look at something 20 feet (6 m) away for 20 seconds. When a
break is due, it gently dims every display and shows a countdown.

## Features

- **Full-screen breaks** on every display, with a countdown ring and a short tip for relaxing
  your eyes and body.
- **Heads-up 10 seconds before a break**, with *Start Now* and *Snooze* buttons. It never takes
  keyboard focus, so you can finish your sentence.
- **Snooze or skip** a break, or turn either off. With skipping off, you can still skip in an
  emergency by holding Esc for 2 seconds.
- **Pauses automatically when you're away**: idle, screen locked, Mac asleep, displays asleep, or
  switched to another user. Time away counts as a break.
- **Holds breaks during calls** while your camera or microphone is in use.
- **Menu-bar countdown** (`18m`, then `42s` in the final minute), and today's break count.
- Pause for 30 minutes, 1 hour, 2 hours or until you resume. Take a break early, or reset the timer.
- Optional chime when a break ends, and optional launch at login.
- Works with VoiceOver, Reduce Motion, Reduce Transparency and Increase Contrast.
- Menu-bar only: no Dock icon, no notifications, no permission prompts.

## Requirements

- macOS 14 Sonoma or later.
- Xcode Command Line Tools (`xcode-select --install`), which include Swift. Full Xcode is not needed.

## Quick start

```sh
make install
```

This builds a release binary, assembles and ad-hoc signs `build/EyeRest.app`, installs it to
`~/Applications`, and opens it. On first launch, EyeRest opens its Settings window with a short
welcome. After that it lives in the menu bar as an eye icon.

To install for all users in `/Applications` instead, run `scripts/build-app.sh --install --system --open`
from an administrator account.

| Command        | What it does                                                            |
| -------------- | ----------------------------------------------------------------------- |
| `make install` | Build, install to `~/Applications` and open                             |
| `make run`     | Build `build/EyeRest.app`, quit any running copy and open the new build |
| `make app`     | Build `build/EyeRest.app` only                                          |
| `make build`   | Debug `swift build` of every target                                     |
| `make test`    | Run the unit tests                                                      |
| `make clean`   | Delete `.build/` and `build/`                                           |

`EYEREST_VERSION` and `EYEREST_BUILD` override the bundle's version and build number,
for example `EYEREST_VERSION=1.1.0 make app`.

## Usage

Click the eye icon in the menu bar:

- **Status**: time to the next break, or why EyeRest is paused.
- **Take a Break Now** (⌘B).
- **Pause** ▸ For 30 Minutes / For 1 Hour / For 2 Hours / Until I Resume. While paused, this becomes **Resume**.
- **Reset Timer**: start a fresh work interval.
- **Today's count** of breaks taken and skipped.
- **Settings…** (⌘,), **About EyeRest**, **Quit EyeRest** (⌘Q).

The icon shows the state: an eye while working, a filled eye on a break, a pause symbol when
paused, and a sleeping moon while you're away.

**Heads-up.** Ten seconds before a break, a small pill appears at the top of the screen with the
pointer: "Eye break in 10 seconds". Click **Start Now** to begin the break right away, or
**Snooze** to postpone it.

**During a break.** Every display dims. Look at something far away until the ring completes.
The break ends by itself; you don't need to click anything. It doesn't steal focus from the app
you were using, so you can carry on typing once the break is over.

| Key or button         | Effect                                                                        |
| --------------------- | ----------------------------------------------------------------------------- |
| **Snooze N min**      | Postpone the break (unless *Snooze* is off)                                   |
| **Skip Break** or Esc | End the break now (if skipping is allowed)                                    |
| Hold Esc for 2 s      | Emergency skip when skipping is turned off                                    |
| Any other key         | Ignored, as is every key in the first second, so typing can't dismiss a break |

**Menu-bar icon hidden?** On a crowded menu bar or behind the notch, open EyeRest again (for
example from Spotlight) to bring up Settings.

## Settings

Changes apply immediately. **Restore Defaults** resets everything except *Open at login*.

| Setting                           | Default     | Options                                              |
| --------------------------------- | ----------- | ---------------------------------------------------- |
| Remind me every                   | 20 min      | 1–120 min                                            |
| Break length                      | 20 sec      | 10, 20, 30, 45 sec · 1, 2, 3, 5 min                  |
| Warn me 10 seconds before a break | On          |                                                      |
| Play a sound when a break ends    | On          |                                                      |
| Allow skipping breaks             | On          |                                                      |
| Snooze                            | 5 min       | Off · 1, 2, 5, 10, 15, 30 min                        |
| Hold breaks during calls          | On          |                                                      |
| Pause when I'm away               | After 5 min | Never · after 2, 3, 5, 10, 15, 30 min                |
| Open at login                     | Off         | Needs the app in `/Applications` or `~/Applications` |
| Show time remaining in menu bar   | On          |                                                      |

## Away detection and call hold

EyeRest treats you as **away** when any of these is true:

- There has been no keyboard, mouse or trackpad input for the *Pause when I'm away* time (unless
  it is set to *Never*).
- The screen is locked, the Mac is asleep, the displays are asleep, or another user is active.
  These apply even with *Pause when I'm away* set to *Never*.

While you're away the timer is frozen. When you come back:

- If you were away for at least one break length, that counts as your break and a fresh interval
  starts.
- Otherwise the timer picks up where it stopped, with at least 15 seconds left.

Locking the screen or sleeping during a break counts the break as completed. Being idle never
interrupts a break. While an app keeps the display awake, as video players and call apps do, you
count as present even without touching anything, and idle time only starts counting once the app
lets go. So watching a video neither pauses your breaks nor counts as one.

**Call hold.** In the last 35 seconds before a break, EyeRest checks whether any app is using the
camera or microphone. If so, the break waits: the status reads "Break on hold while you're on a
call", and the countdown and heads-up are hidden. About 30 seconds after the call ends, the break
arrives as usual, with its heads-up. Headphones that are only playing audio don't count as a call.

## Privacy

- No network access, accounts, analytics or telemetry.
- No permission prompts: EyeRest doesn't need Accessibility, Screen Recording, Camera, Microphone
  or Notifications access.
- Idle detection reads only the time since your last input, never which keys you pressed.
- Call detection reads only whether the camera or microphone is *in use*. EyeRest never captures
  audio or video.
- Settings and today's break counts are stored locally in the app's preferences.

## Uninstall

1. Choose **Quit EyeRest** from its menu.
2. If you turned on *Open at login*, remove EyeRest in System Settings › General › Login Items.
3. Delete the app: `rm -rf ~/Applications/EyeRest.app` (or `/Applications/EyeRest.app`).
4. Remove its preferences: `defaults delete com.balraj.EyeRest`.

## Project layout

```
Package.swift             SwiftPM package (no Xcode project)
Sources/
  EyeRestCore/            Break scheduler state machine, settings, daily stats, status text.
                          Foundation only, so it is unit-tested headlessly.
  EyeRestSystem/          OS signals: idle time, lock/sleep/display/session changes,
                          camera and microphone in use, the end-of-break chime.
  EyeRestUI/              Break overlay, heads-up and settings window (AppKit + SwiftUI).
  EyeRest/                The menu-bar app that wires everything together.
Tests/EyeRestCoreTests/   Swift Testing suite for EyeRestCore.
Resources/Info.plist      Bundle metadata (menu-bar-only app, com.balraj.EyeRest).
scripts/build-app.sh      Builds, assembles, signs and optionally installs and opens EyeRest.app.
scripts/make-icon.swift   Draws the app icon at every size for iconutil.
Makefile                  Shortcuts for the commands above.
```

## Running tests

```sh
make test        # or: swift test
```

The tests use [Swift Testing](https://github.com/swiftlang/swift-testing), which works with the
Command Line Tools alone. They cover the core logic: the break scheduler (including a randomized
test of its invariants), settings, daily stats and the formatted text.

For quick iteration you can also run the app unbundled with `swift run EyeRest`. In that mode
*Open at login* and the single-instance check are unavailable. `make run` tests the real bundle
from `build/`, but *Open at login* only works in an installed copy (`make install`).
