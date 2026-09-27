# EyeRest

EyeRest is a small, native macOS menu-bar app that reminds you to rest your eyes using the
**20-20-20 rule**: every 20 minutes, look at something 20 feet (6 m) away for 20 seconds. When a
reminder is due, a Frutiger Aero glass card floats in at the top right of the screen, counts down
and closes itself. It never blocks anything: keep working, or look away.

## Features

- **Gentle, non-blocking reminder** every *N* minutes: a small card under the menu bar, like a
  notification, with a countdown orb and a **Done** button. It never takes focus, so your typing
  carries on.
- Appears on every Space and over full-screen apps, on the screen with the pointer.
- An optional soft sound when the card appears.
- **Menu-bar countdown** (`18m`, then `42s` in the final minute).
- Pause for 30 minutes, 1 hour, 2 hours or until you resume. Get a reminder right away, or reset the timer.
- Starts over after sleep, screen lock or a switch to another user.
- Optional launch at login.
- Works with VoiceOver, Reduce Motion, Reduce Transparency and Increase Contrast.
- Menu-bar only: no Dock icon, no permission prompts, nothing tracked.

## Requirements

- macOS 14 Sonoma or later.
- Xcode Command Line Tools (`xcode-select --install`), which include Swift. Full Xcode is not needed.

## Quick start

```sh
make install
```

This builds a release binary, assembles and ad-hoc signs `build/EyeRest.app`, installs it to
`~/Applications`, and opens it. EyeRest lives in the menu bar as an eye icon; the first reminder
arrives 20 minutes later.

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

- **Status**: "Next reminder in 18:42", "Resting — 0:12 left" while the card is up,
  "Paused until 3:45 PM" or "Paused".
- **Remind Me Now** (⌘R): show the card now (this also ends a pause). Hidden while the card is up.
- **Pause** ▸ For 30 Minutes / For 1 Hour / For 2 Hours / Until I Resume. Pausing closes the card if
  it is up. While paused, this item becomes **Resume**, which starts a fresh interval.
- **Reset Timer**: restart the countdown to the next reminder.
- **Settings…** (⌘,), **About EyeRest**, **Quit EyeRest** (⌘Q).

The shortcuts work while the menu is open; EyeRest registers no global hotkeys. The icon shows the
state: an eye while counting down, a filled eye while the card is up, and a pause symbol when paused.

**The reminder card.** It reads "Time to rest your eyes" and "Look at something 20 feet (6 m) away.",
with the time left (`0:17`) in a glossy ring. When the countdown ends, the card fades out by itself;
click **Done** to close it early. Either way, the next interval starts when the card closes. The card
never becomes the active window and never activates EyeRest, so the app you're using keeps the
keyboard, and the rest of the screen stays fully usable. A single click on **Done** works even while
another app is active. EyeRest doesn't watch your input, so if you're away the card simply closes on
schedule. VoiceOver announces the card once when it appears, and with Reduce Motion it appears and
disappears without animation.

**Menu-bar icon hidden?** On a crowded menu bar or behind the notch, open EyeRest again (for
example from Spotlight) to bring up Settings.

## Settings

Changes apply immediately; a new interval restarts the countdown, and a new reminder length applies
from the next card. **Restore Defaults** resets everything except *Open at login*.

| Setting                         | Default | Options                                              |
| ------------------------------- | ------- | ---------------------------------------------------- |
| Remind me every                 | 20 min  | 1–120 min                                            |
| Look away for                   | 20 sec  | 10, 20, 30, 45 or 60 sec                             |
| Play a sound                    | On      | A soft system sound when the card appears            |
| Show time remaining in menu bar | On      | `18m`, then `42s` in the final minute                |
| Open at login                   | Off     | Needs the app in `/Applications` or `~/Applications` |

## Sleep, lock and time away

While the Mac is asleep, the screen is locked, the displays are asleep or another user is switched
in, the timer stops and a visible card closes. Once all of that is over, a fresh interval starts, so a
reminder never greets you the moment you unlock. If EyeRest misses more than a minute without being
told why (a sleep it didn't hear about, say), it also starts a fresh interval. Setting the clock back
keeps the time remaining, and a pause stays in place through sleep and lock.

That is all EyeRest observes. It doesn't track keyboard, mouse or idle time, doesn't check the camera
or microphone, and keeps no stats or history.

## Privacy

- No network access, accounts, analytics or telemetry.
- No permission prompts: EyeRest doesn't need Accessibility, Screen Recording, Camera, Microphone
  or Notifications access.
- Nothing is tracked. EyeRest only listens for the system's sleep, lock, display-sleep and
  user-switch notifications.
- Your settings are the only thing it stores, locally in the app's preferences.

## Design

The card and the app icon follow **Frutiger Aero**, the glossy mid-2000s look of sky-blue gradients,
glass, bubbles and fresh green: a frosted glass pane, a glass countdown orb with rising bubbles and
an aqua gel **Done** button. The icon is an eye over a sunlit meadow under a clear sky. In Dark Mode
the glass is tinted down a step. The look has a few deliberate limits:

- **The menu-bar icon stays monochrome.** macOS expects menu-bar icons to be template images, so it
  is a plain SF Symbol that adapts to light and dark menu bars. The colour lives in the card and the
  app icon.
- **Avenir Next instead of Frutiger.** Frutiger doesn't ship with macOS and isn't bundled, so the card
  uses Avenir Next, also by Adrian Frutiger, which does.
- **Everything is drawn in code.** The card is SwiftUI gradients and highlights, and
  `scripts/make-icon.swift` draws the app icon with Core Graphics at build time; the repository holds
  no image files. The glass is painted rather than a live blur of what's behind it, so it is nearly
  opaque and stays readable over busy windows. Reduce Transparency makes it fully opaque, and Increase Contrast
  strengthens its text and borders.
- **No system Liquid Glass.** That material needs the macOS 26 SDK; EyeRest draws its own glass and
  looks the same on every macOS version from 14 up.

## Uninstall

1. Choose **Quit EyeRest** from its menu.
2. If you turned on *Open at login*, remove EyeRest in System Settings › General › Login Items.
3. Delete the app: `rm -rf ~/Applications/EyeRest.app` (or `/Applications/EyeRest.app`).
4. Remove its preferences: `defaults delete com.balraj.EyeRest`.

## Project layout

```
Package.swift             SwiftPM package (no Xcode project)
Sources/
  EyeRestCore/            Reminder scheduler state machine, settings, status text and time formatting.
                          Foundation only, so it is unit-tested headlessly.
  EyeRestUI/              The reminder card, its Frutiger Aero style and the Settings window
                          (AppKit + SwiftUI).
  EyeRest/                The menu-bar app: status item and menu, sleep/lock observers, and the
                          wiring between them.
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
Command Line Tools alone. They cover the core logic: the reminder scheduler (including a randomized
test of its invariants), settings decoding and storage, and the formatted text. Tests that need
`UserDefaults` use a throwaway store in a temporary folder, never your real preferences.

For quick iteration you can also run the app unbundled with `swift run EyeRest`. In that mode
*Open at login* and the single-instance check are unavailable. `make run` tests the real bundle
from `build/`, but *Open at login* only works in an installed copy (`make install`).
