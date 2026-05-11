# rbx-virtual-piano-ahk

An AutoHotkey v2 script that plays MIDI files on Roblox piano keyboards automatically. Parses raw `.mid` files, maps notes to keyboard keys, and handles black keys via Shift combos — no external dependencies required.

## Requirements

- [AutoHotkey v2.0+](https://www.autohotkey.com/)
- Windows 10/11
- A Roblox piano game (e.g. Virtual Piano, Piano Keyboard)

## Setup

1. Place `jjs_piano.ahk` anywhere (Desktop works fine). OR Go to releases and download the `latest .exe` file
2. Drop your MIDI files in the **same folder** or on the **Desktop**.
3. Name them with a slot prefix:

| File Name | Hotkey |
|-----------|--------|
| `p1_songname.mid` | `Ctrl+Shift+1` |
| `p2_songname.mid` | `Ctrl+Shift+2` |
| `p3_songname.mid` | `Ctrl+Shift+3` |
| ... | ... |
| `p0_songname.mid` | `Ctrl+Shift+0` |

4. Double-click `jjs_piano.ahk` to run.
5. Open Roblox, join a piano game, and press the hotkey for your slot.

## Controls

All controls **only work while Roblox is focused** — they won't interfere with other apps.

| Key | Action |
|-----|--------|
| `Ctrl+Shift+1‑0` | Play MIDI slot 1–10 |
| `Space` | **Instant stop** — releases all held keys immediately |
| `]` | Speed up (+0.25× per press) |
| `[` | Slow down (-0.25× per press, min 0.25×) |

### Speed

- Default speed is `1.0×` (original tempo).
- `]` increases: `1.0 → 1.25 → 1.5 → 1.75 → 2.0×` etc.
- `[` decreases: `1.0 → 0.75 → 0.5 → 0.25×` (minimum).
- Speed **resets to 1.0×** automatically after every stop or song finish.
- Speed changes take effect **live** during playback — the song won't jump.

## Features

- **Full MIDI parsing** — reads multi-track `.mid` files natively (no converters needed)
- **Black key support** — uses `LShift` + physical key combos with a shift-counter for simultaneous black keys
- **Drum channel skip** — MIDI channel 10 (drums) is filtered out so drum hits don't produce garbage
- **Smart octave shift** — automatically shifts the entire song to fit the 36-key layout while preserving intervals
- **Auto-stop on unfocus** — if Roblox loses focus during playback, the script stops immediately (no stuck keys)
- **High-resolution timing** — uses `QueryPerformanceCounter` for sub-millisecond accuracy
- **Bracket-safe file search** — handles filenames with `[brackets]` and special characters correctly
- **Desktop search** — finds MIDI files in the script directory, Desktop, and OneDrive Desktop

## File Naming Examples

```
p1_River Flows In You.mid
p2_Moonlight Sonata.mid
p3_Unravel (Tokyo Ghoul).mid
p4_Giorno's Theme [Jojo's Bizarre Adventure] (WIP).mid
p0_Never Gonna Give You Up.mid
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Nothing happens when I press `Ctrl+Shift+N` | Make sure Roblox is the active window |
| "No file found for slot N" | Check the filename starts with `pN_` and ends with `.mid` |
| Notes sound wrong / too high / too low | The auto-octave-shift picks the best fit — try a different MIDI arrangement |
| Keys get stuck | Press `Space` to force-release all keys, or restart the script |
| Script won't start | Make sure you have AutoHotkey **v2** installed (not v1) |

## License

Do whatever you want with it. No warranty.
