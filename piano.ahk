#Requires AutoHotkey v2.0
#SingleInstance Force

; piano.ahk — Roblox Piano MIDI Player
;
; Place MIDI files next to this script (or on Desktop):
;   p1_songname.mid → Ctrl+Shift+1  ...  p0_songname.mid → Ctrl+Shift+0
;
; During playback (Roblox only):
;   Space   → Instant stop
;   ]       → Speed up   (+0.25×, e.g. 1.0 → 1.25 → 1.5 → 2.0)
;   [       → Slow down  (-0.25×, min 0.25×)
;
; Speed resets to 1.0× after every stop or song finish.
; Auto-stops if Roblox loses focus.

global SpeedMult   := 1.0
global StopMacro   := false
global IsPlaying   := false
global PlayStartMs := 0.0

; Auto-stop when Roblox loses focus during playback
SetTimer(_CheckFocus, 200)
_CheckFocus() {
    global StopMacro, IsPlaying
    if IsPlaying && !WinActive("Roblox")
        StopMacro := true
}

; --- Key Maps ---

global WhiteNoteMap := Map()
global BlackKeyMap  := Map()

_BuildMaps() {
    global WhiteNoteMap, BlackKeyMap

    whiteKeys := ["1","2","3","4","5","6","7","8","9","0",
                  "q","w","e","r","t","y","u","i","o","p",
                  "a","s","d","f","g","h","j","k","l","z",
                  "x","c","v","b","n","m"]
    whites := [0,2,4,5,7,9,11]
    wi := 1
    Loop 6 {
        octBase := 48 + (A_Index - 1) * 12
        for _, semi in whites {
            if wi > whiteKeys.Length
                break
            WhiteNoteMap[octBase + semi] := whiteKeys[wi]
            wi++
        }
    }

    blackDefs := [
        {key:"1",shift:true},  {key:"2",shift:true},  {key:"4",shift:true},
        {key:"5",shift:true},  {key:"6",shift:true},  {key:"8",shift:true},
        {key:"9",shift:true},  {key:"q",shift:true},  {key:"w",shift:true},
        {key:"e",shift:true},  {key:"t",shift:true},  {key:"y",shift:true},
        {key:"i",shift:true},  {key:"o",shift:true},  {key:"p",shift:true},
        {key:"s",shift:true},  {key:"d",shift:true},  {key:"g",shift:true},
        {key:"h",shift:true},  {key:"j",shift:true},  {key:"l",shift:true},
        {key:"z",shift:true},  {key:"c",shift:true},  {key:"v",shift:true},
        {key:"b",shift:true}
    ]
    blackNotes := [49,51,54,56,58,61,63,66,68,70,73,75,78,80,82,85,87,90,92,94,97,99,102,104,106]
    Loop blackNotes.Length
        BlackKeyMap[blackNotes[A_Index]] := blackDefs[A_Index]
}
_BuildMaps()

; --- Binary Helpers ---

_ReadByte(buf, &pos) {
    b := NumGet(buf, pos, "UChar")
    pos++
    return b
}
_ReadWord(buf, &pos) {
    hi := _ReadByte(buf, &pos)
    lo := _ReadByte(buf, &pos)
    return (hi << 8) | lo
}
_ReadDWord(buf, &pos) {
    b0 := _ReadByte(buf, &pos)
    b1 := _ReadByte(buf, &pos)
    b2 := _ReadByte(buf, &pos)
    b3 := _ReadByte(buf, &pos)
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}
_ReadVLQ(buf, &pos) {
    val := 0
    Loop {
        b := _ReadByte(buf, &pos)
        val := (val << 7) | (b & 0x7F)
        if !(b & 0x80)
            break
    }
    return val
}

; --- Shell Sort (iterative) ---

_ShellSort(arr) {
    n   := arr.Length
    gap := n // 2
    while gap > 0 {
        i := gap + 1
        Loop n - gap {
            temp := arr[i]
            j    := i
            while j > gap {
                prev := arr[j - gap]
                if prev.tick > temp.tick || (prev.tick = temp.tick && prev.order > temp.order) {
                    arr[j] := prev
                    j      -= gap
                } else {
                    break
                }
            }
            arr[j] := temp
            i++
        }
        gap := gap // 2
    }
}

; --- MIDI Parser ---

ParseMidi(filePath) {
    global WhiteNoteMap, BlackKeyMap
    events := []

    if !FileExist(filePath) {
        MsgBox("No file found:`n" filePath, "MIDI Player", "Icon!")
        return events
    }
    f := FileOpen(filePath, "r")
    if !f {
        MsgBox("Failed to open:`n" filePath, "MIDI Player", "Icon!")
        return events
    }
    fileSize := f.Length
    buf := Buffer(fileSize)
    f.RawRead(buf, fileSize)
    f.Close()

    pos := 0
    if (_ReadDWord(buf, &pos) != 0x4D546864) {
        MsgBox("Not a valid MIDI file.", "MIDI Player", "Icon!")
        return events
    }
    _ReadDWord(buf, &pos)
    _ReadWord(buf, &pos)
    numTracks := _ReadWord(buf, &pos)
    division  := _ReadWord(buf, &pos)

    rawEvents := []

    Loop numTracks {
        chunkID  := _ReadDWord(buf, &pos)
        chunkLen := _ReadDWord(buf, &pos)
        chunkEnd := pos + chunkLen

        if (chunkID != 0x4D54726B) {
            pos := chunkEnd
            continue
        }

        absTick   := 0
        runStatus := 0

        while pos < chunkEnd {
            absTick += _ReadVLQ(buf, &pos)
            statusByte := NumGet(buf, pos, "UChar")

            if statusByte = 0xFF {
                pos++
                metaType := _ReadByte(buf, &pos)
                metaLen  := _ReadVLQ(buf, &pos)
                if (metaType = 0x51 && metaLen = 3) {
                    b0 := _ReadByte(buf, &pos)
                    b1 := _ReadByte(buf, &pos)
                    b2 := _ReadByte(buf, &pos)
                    rawEvents.Push({tick: absTick, type: "tempo", tempo: (b0 << 16) | (b1 << 8) | b2, order: 0, ch: -1})
                } else {
                    pos += metaLen
                }
                runStatus := 0
                continue
            }

            if (statusByte = 0xF0 || statusByte = 0xF7) {
                pos++
                pos += _ReadVLQ(buf, &pos)
                runStatus := 0
                continue
            }

            if (statusByte & 0x80) {
                runStatus := statusByte
                pos++
            }

            evType := (runStatus >> 4) & 0xF
            evCh   := runStatus & 0xF

            if evType = 0x9 {
                note := _ReadByte(buf, &pos)
                vel  := _ReadByte(buf, &pos)
                if evCh = 9
                    continue
                evOn := (vel > 0) ? "on" : "off"
                rawEvents.Push({tick: absTick, type: evOn, note: note, order: (evOn = "on") ? 1 : 0, ch: evCh})
            } else if evType = 0x8 {
                note := _ReadByte(buf, &pos)
                _ReadByte(buf, &pos)
                if evCh = 9
                    continue
                rawEvents.Push({tick: absTick, type: "off", note: note, order: 0, ch: evCh})
            } else if (evType = 0xA || evType = 0xB || evType = 0xE) {
                pos += 2
            } else if (evType = 0xC || evType = 0xD) {
                pos += 1
            } else {
                pos += 1
            }
        }
        pos := chunkEnd
    }

    if rawEvents.Length > 1
        _ShellSort(rawEvents)

    ; Global octave shift — find the offset that puts the most notes in mapped range
    globalShift := 0
    {
        noteList := []
        for _, ev in rawEvents {
            if ev.type = "on" || ev.type = "off"
                noteList.Push(ev.note)
        }
        if noteList.Length > 0 {
            bestCount := -1
            Loop 11 {
                sh    := (A_Index - 6) * 12
                count := 0
                for _, n in noteList {
                    sn := n + sh
                    if sn >= 48 && sn <= 108
                        count++
                }
                if count > bestCount {
                    bestCount   := count
                    globalShift := sh
                }
            }
        }
    }

    curTempo := 500000
    prevTick := 0
    accumMs  := 0.0

    for _, ev in rawEvents {
        tickDelta := ev.tick - prevTick
        accumMs   += (tickDelta / division) * curTempo / 1000.0
        prevTick  := ev.tick

        if ev.type = "tempo" {
            curTempo := ev.tempo
            continue
        }

        note := ev.note + globalShift
        while note < 48
            note += 12
        while note > 108
            note -= 12

        keyObj  := ""
        isBlack := false
        if WhiteNoteMap.Has(note)
            keyObj := WhiteNoteMap[note]
        else if BlackKeyMap.Has(note) {
            keyObj  := BlackKeyMap[note]
            isBlack := true
        }
        if keyObj = ""
            continue

        events.Push({rawMs: accumMs, type: ev.type, keyObj: keyObj, isBlack: isBlack})
    }

    return events
}

; --- High-Resolution Timer ---

_QPCms() {
    static freq     := 0
    static initDone := false
    if !initDone {
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
        initDone := true
    }
    local cnt := 0
    DllCall("QueryPerformanceCounter", "Int64*", &cnt)
    return (cnt / freq) * 1000.0
}

; --- Precise Wait ---

_WaitUntil(rawMs) {
    global StopMacro, PlayStartMs, SpeedMult
    Target() => PlayStartMs + rawMs / SpeedMult
    remaining := Target() - _QPCms()
    if remaining <= 0
        return
    ; Break long sleeps into 15ms chunks so StopMacro is checked frequently
    while remaining > 15 {
        if StopMacro
            return
        Sleep(10)
        remaining := Target() - _QPCms()
    }
    ; Spin-wait the final few ms for precision
    Loop {
        if StopMacro
            return
        if _QPCms() >= Target()
            break
    }
}

; --- Play Engine ---

_ReleaseAll(heldKeys, &shiftCount) {
    for physKey, info in heldKeys {
        SendInput("{" physKey " up}")
        if info.shift
            shiftCount--
    }
    if shiftCount != 0 {
        SendInput("{LShift up}")
        shiftCount := 0
    }
    heldKeys.Clear()
}

PlayMidi(events) {
    global StopMacro, PlayStartMs
    heldKeys   := Map()
    shiftCount := 0
    PlayStartMs := _QPCms()

    for _, ev in events {
        if StopMacro {
            _ReleaseAll(heldKeys, &shiftCount)
            return
        }

        _WaitUntil(ev.rawMs)

        if StopMacro {
            _ReleaseAll(heldKeys, &shiftCount)
            return
        }

        physKey  := ev.isBlack ? ev.keyObj.key : ev.keyObj
        needShft := ev.isBlack ? ev.keyObj.shift : false

        if ev.type = "on" {
            if !heldKeys.Has(physKey) {
                if needShft {
                    if shiftCount = 0
                        SendInput("{LShift down}")
                    shiftCount++
                } else {
                    if shiftCount > 0
                        SendInput("{LShift up}")
                    SendInput("{" physKey " down}")
                    if shiftCount > 0
                        SendInput("{LShift down}")
                    heldKeys[physKey] := {shift: false, count: 1}
                    continue
                }
                SendInput("{" physKey " down}")
                heldKeys[physKey] := {shift: needShft, count: 1}
            }
        } else {
            if heldKeys.Has(physKey) {
                info := heldKeys[physKey]
                SendInput("{" physKey " up}")
                heldKeys.Delete(physKey)
                if info.shift {
                    shiftCount--
                    if shiftCount = 0
                        SendInput("{LShift up}")
                }
            }
        }
    }

    _ReleaseAll(heldKeys, &shiftCount)
}

; --- Find MIDI File ---

FindMidi(slot) {
    prefix      := "p" (slot = 10 ? "0" : slot) "_"
    userProfile := EnvGet("USERPROFILE")

    searchDirs := [
        A_ScriptDir,
        A_Desktop,
        userProfile "\Desktop",
        userProfile "\OneDrive\Desktop"
    ]

    for _, dir in searchDirs {
        if !DirExist(dir)
            continue
        Loop Files, dir "\*.mid" {
            if SubStr(A_LoopFileName, 1, StrLen(prefix)) = prefix
                return A_LoopFileFullPath
        }
    }
    return ""
}

; --- Play Routine ---

DoPlay(slot) {
    global StopMacro, SpeedMult, IsPlaying

    if !WinActive("Roblox")
        return

    StopMacro := true
    Sleep(50)
    StopMacro := false

    path := FindMidi(slot)
    if path = "" {
        label := (slot = 10) ? "0" : slot
        MsgBox("No file found for slot " label ".`nExpected: p" label "_songname.mid`nIn: " A_ScriptDir " or Desktop", "MIDI Player", "Icon!")
        return
    }

    midiData := ParseMidi(path)
    if midiData.Length = 0 {
        MsgBox("No playable notes in:`n" path, "MIDI Player", "Icon!")
        return
    }

    savedKeyDelay    := A_KeyDelay
    savedKeyDuration := A_KeyDuration
    SetKeyDelay(-1, -1)

    IsPlaying := true
    PlayMidi(midiData)

    SetKeyDelay(savedKeyDelay, savedKeyDuration)
    SpeedMult := 1.0
    IsPlaying := false
}

; --- Hotkeys (Roblox only) ---

#HotIf WinActive("Roblox")

^+1:: DoPlay(1)
^+2:: DoPlay(2)
^+3:: DoPlay(3)
^+4:: DoPlay(4)
^+5:: DoPlay(5)
^+6:: DoPlay(6)
^+7:: DoPlay(7)
^+8:: DoPlay(8)
^+9:: DoPlay(9)
^+0:: DoPlay(10)

~Space:: {
    global StopMacro, SpeedMult
    StopMacro := true
    SpeedMult := 1.0
}

_ChangeSpeed(newSpeed) {
    global SpeedMult, PlayStartMs, IsPlaying
    if IsPlaying {
        now     := _QPCms()
        songPos := (now - PlayStartMs) * SpeedMult
        SpeedMult   := newSpeed
        PlayStartMs := now - songPos / SpeedMult
    } else {
        SpeedMult := newSpeed
    }
}

~[:: {
    global SpeedMult
    _ChangeSpeed(Max(0.25, Round(SpeedMult - 0.25, 2)))
    ToolTip("Speed: " SpeedMult "×")
    SetTimer(() => ToolTip(), -1500)
}

~]:: {
    global SpeedMult
    _ChangeSpeed(Round(SpeedMult + 0.25, 2))
    ToolTip("Speed: " SpeedMult "×")
    SetTimer(() => ToolTip(), -1500)
}

#HotIf
