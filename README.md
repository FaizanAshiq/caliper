# Caliper

A menu bar app that measures distances on screen, in the same logical points your
code is written in. Press Control+Shift+M anywhere, drag, and the number is on your
clipboard.

<!-- Image goes here once there is one -->

## Install

```bash
brew install faizanashiq/tap/caliper
```

Or clone and build:

```bash
git clone https://github.com/FaizanAshiq/caliper.git
cd caliper
./build.sh release --install
```

Both compile on your machine, which is what keeps first launch clean. See below for
why that matters.

## Using it

| Mode | How you start it | What you get |
| --- | --- | --- |
| Ruler line | Drag | Distance, plus dx and dy |
| Marquee box | Press `M` to switch, then drag | Width by height |
| Edge snap | Click without dragging | Bounds of the element under the cursor, and the gaps to its neighbours |
| Guide | Press `G` | A line that stays on screen after the overlay closes |

| Input | Effect |
| --- | --- |
| `Control+Shift+M` | Arm or dismiss the overlay |
| `Shift` while drawing | Constrain to 0, 45 or 90 degrees, or square the marquee |
| `Space` while drawing | Reposition the whole shape, size and angle locked |
| `Option` while drawing | Draw the marquee out from its centre |
| Arrow keys | Nudge the active endpoint by 1 pt |
| `Shift` plus arrow keys | Nudge by 10 pt |
| `Option+G` | Drop a horizontal guide instead of a vertical one |
| `Shift+G` | Clear every guide |
| `R` | Re-read the screen |
| `Cmd+C` | Copy the value |
| `Esc` | Dismiss |

## What the numbers mean

Caliper reports logical points, the unit CSS, SwiftUI, AppKit and Figma all call a
pixel, and optionally backing pixels alongside. On a 2x display a 16 pt gap is 32
backing pixels, so precision stops at half a point and the readout shows one decimal
to match.

It never reports physical panel pixels. On a scaled display that number is not a whole
multiple of either of the other two, macOS does not report it, and no code you write
refers to it. Printing it would be inventing precision.

## Permissions

The ruler, the marquee, guides, nudging and copying need no permissions at all, and
nothing is requested when you launch.

The loupe, the eyedropper and edge snapping read what is on screen, so they need
Screen Recording. Caliper asks the first time you reach for one, from the menu bar
item, and stays useful if you say no.

## Settings

Four settings live in the menu under Settings. Everything else, including the hotkey,
is in `~/Library/Application Support/Caliper/preferences.json`. Every key in that file
is optional, so you can delete down to the one line you care about and the rest falls
back to defaults.

## Building

Swift 6, Command Line Tools, no Xcode and no dependencies.

```bash
swift build          # compile
./test.sh            # run the tests
./build.sh           # produce dist/Caliper.app
```

`test.sh` exists because with Command Line Tools and no Xcode installed, Swift Package
Manager does not load the Swift Testing macro plugin, so plain `swift test` fails to
expand `@Test` at all. The script points the compiler at the plugin when it finds it
and falls straight through to `swift test` when it does not.

## Why install from source

Caliper is not notarised, because notarisation needs a paid Apple Developer
account. Since macOS Sequoia, Apple removed the Control-click shortcut for
opening un-notarised apps, so a downloaded copy would make you visit System
Settings, Privacy and Security, and click Open Anyway before it would run.

Quarantine is only applied to downloaded files. Building on your own machine
skips all of that, which is why the Homebrew formula compiles rather than
pulling a binary.

One consequence worth knowing: an ad hoc signature is a hash of the binary, so
every upgrade looks like a new app to macOS and Screen Recording has to be
granted again. That goes away if Caliper ever gets a Developer ID.

## License

MIT
