#Requires AutoHotkey v2.0
; =====================================================================
;  ED Trip Helper
;  Vibe coded with the legendary Claude by Bendersordoexchao.com.au
;  Latest version: https://github.com/Barkeep-Bender/ED-Trip-Helper
;  Enjoying it? Shout me a coffee: https://buymeacoffee.com/bendersordoexchao
;  Copyright (c) 2026 Ben Rainbird (Bender's Ordo ex Chao). All rights reserved
;  except as granted by the licence below.
;  Licensed under the PolyForm Noncommercial License 1.0.0:
;  https://polyformproject.org/licenses/noncommercial/1.0.0
;  Required Notice: Copyright 2026 Ben Rainbird (Bendersordoexchao.com.au)
;  Free to use, share and modify for non-commercial purposes - keep this notice.
;  Commercial use or resale needs written permission.
; =====================================================================
#SingleInstance Force

; Run as admin so keypresses reach Elite even if the game/launcher runs elevated
if !A_IsAdmin {
    try Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"'
    ExitApp
}


; All hotkeys only work while Elite is the active window, so F8-F12 stay
; free for other programs the rest of the time.
; F8 = key test: after 3 s, presses UiUp 3x (scan codes) then 3x (normal method)
#HotIf WinActive("ahk_exe EliteDangerous64.exe")
F8:: KeyTest()
#HotIf
KeyTest() {
    Say("Key test in 3 s - click into the window you want to test", 3000)
    Sleep 3000
    key := K["UiUp"]
    ok := 0
    Loop 3 {
        ok += SendSC(key, false)
        Sleep 100
        ok += SendSC(key, true)
        Sleep 300
    }
    Sleep 800
    Loop 3 {
        SendEvent "{" key " down}"
        Sleep 100
        SendEvent "{" key " up}"
        Sleep 300
    }
    Say("Key test done. Scan-code presses accepted by Windows: " ok "/6   Active: " WinGetProcessName("A"), 8000)
}

; F11 = diagnostic: shows which program Windows thinks is active
#HotIf WinActive("ahk_exe EliteDangerous64.exe")
F11:: Say("Active program: " WinGetProcessName("A") "   Admin: " (A_IsAdmin ? "yes" : "no"), 6000)
#HotIf
; =====================================================================
;  Elite Dangerous trip helper:  Launch -> Supercruise -> Drop -> Dock
; ---------------------------------------------------------------------
;  F9  = full trip: launch, clear mass lock, supercruise, let SC Assist
;        fly you in, then request docking (ADC lands you)
;        Already in supercruise (e.g. after your own jumps)? Lock the station,
;        point at it, press F9 once - it goes straight to SC Assist and docking.
;  F10 = dropped out near a station yourself? Full throttle toward it for
;        DOCK_DELAY_SEC (18 s), then request docking - same as the end of F9
;  F12 = abort (throttle to zero, macro stops)
;
;  Ship needs: Advanced Docking Computer + Supercruise Assist module.
;  Orbital stations and fleet carriers only - NOT planetary ports/settlements
;  (Supercruise Assist parks you in orbital cruise, so it never lands).
;  Lock your destination in the LEFT PANEL (Navigation tab) before pressing F9,
;  and leave the panel on the Navigation tab - the script counts tabs from there.
;  All hotkeys (F8-F12) only work while Elite is the active window.
; =====================================================================

; ---------- YOUR KEYBINDS: change these to match Elite's Options > Controls ----------
; "Speed75" and "Speed100" = SHIP CONTROLS > FLIGHT THROTTLE > SET SPEED TO 75% / 100%
; (not bound by default - bind them in game to the keys below, or change these)
; "Supercruise" = SHIP CONTROLS > FLIGHT MISCELLANEOUS > SUPERCRUISE
K := Map(
    "UiUp", "w",
    "UiDown", "s",
    "UiLeft", "a",
    "UiRight", "d",
    "UiSelect", "Space",
    "LeftPanel", "1",
    "NextTab", "e",
    "PrevTab", "q",
    "Speed0", "x",
    "Speed75", "Numpad7",
    "Speed100", "Numpad9",
    "Boost", "Tab",
    "Supercruise", "j"
)

; ---------- TIMINGS ----------
HANDOFF_SEC    := 12   ; fallback only: fixed wait after undocking if the ADC handover can't be detected
ADC_MAX_SEC    := 300  ; give up waiting for the ADC (e.g. long traffic queue) after this many seconds
DOCK_DELAY_SEC := 18   ; after SC Assist drops you out, fly on this long before requesting docking
RETRY_SEC      := 10   ; if docking is denied for distance, fly in this long before asking again
DOCK_TRIES     := 12   ; give up after this many attempts (12 x 10 s = 2 minutes of approach)

; ---------- LAUNCH KEY SEQUENCE ----------
; Docked menu = icon row, (Starport/Construction Services), AUTO LAUNCH, DISEMBARK.
; Go all the way down to Disembark, then up one to Auto Launch, then select.
LAUNCH_SEQUENCE := ["UiDown", "UiDown", "UiDown", "UiDown", "UiDown", "UiUp", "UiSelect"]

; ---------- DOCKING REQUEST KEY SEQUENCE (the bit most likely to need tuning) ----------
; Opens left panel, rewinds to first tab, steps to CONTACTS (3rd tab),
; selects the station, moves to REQUEST DOCKING, selects it, closes panel.
; Do it by hand once and adjust this list to match what you actually press.
; The left panel's tabs wrap round, so every sequence starts AND ends on the
; NAVIGATION tab: we step E,E across to CONTACTS, then Q,Q back again.
; A,A first makes sure we're on the station row, not a leftover button.
DOCK_SEQUENCE := ["LeftPanel", "NextTab", "NextTab", "UiLeft", "UiLeft", "UiRight", "UiSelect",
                  "PrevTab", "PrevTab", "LeftPanel"]

; ---------- SUPERCRUISE ASSIST KEY SEQUENCE ----------
; In supercruise: open left panel (Navigation tab, your locked destination still
; highlighted), open it, step right from LOCK DESTINATION to SUPERCRUISE ASSIST, select.
SCA_SEQUENCE := ["LeftPanel", "UiSelect", "UiRight", "UiSelect", "LeftPanel"]

; ---------- SLOW MOTION (for watching what it presses) ----------
SLOW_MODE := false     ; true = about one keypress per second

; ---------- MESSAGE DISPLAY ----------
OSD_FONT      := "Segoe UI"   ; font name
OSD_FONT_SIZE := 16           ; text size
OSD_COLOR     := "FF8C00"     ; text colour (Elite orange)
OSD_BG        := "000000"     ; background colour (black)
OSD_X         := 20           ; position from left of screen
OSD_Y         := 20           ; position from top of screen
OSD_WIDTH     := 760          ; box width - long messages wrap
OSD_OPACITY   := 170          ; 0 = invisible, 255 = solid (affects text and background)

; ---------- internals (no need to touch) ----------
ED_DIR        := EnvGet("USERPROFILE") "\Saved Games\Frontier Developments\Elite Dangerous"
FLAG_DOCKED   := 0x1
FLAG_SC       := 0x10
FLAG_MASSLOCK := 0x10000
Running   := false
LastFlags := 0
AwaitingAlign := false
OSD := 0
OSDText := 0

#HotIf WinActive("ahk_exe EliteDangerous64.exe")
; Wait for the F-key to be released first, otherwise Elite sees "F9 + W"
; as a modifier combo and ignores it
F9:: {
    global AwaitingAlign
    KeyWait "F9"
    Sleep 300
    if AwaitingAlign {                      ; second press = "I'm lined up, carry on"
        AwaitingAlign := false
        return
    }
    SetTimer RunTrip, -1                    ; run in its own thread so F9 stays free for the 2nd press
}
F10:: {
    KeyWait "F10"
    Sleep 300
    if Running {                            ; a trip is already in progress
        Say("Busy with a trip - press F12 to abort it first.", 4000)
        return
    }
    SetTimer ApproachAndDock, -1            ; same as the end of an F9 trip: close in, then request
}
F12:: Abort()
#HotIf

Say("Loaded - by Bendersordoexchao.com.au. F9 trip, F10 dock, F11 check, F12 abort.", 5000)

RunTrip() {
    global Running, AwaitingAlign
    if Running
        return
    Running := true

    ; Already in supercruise (e.g. just arrived after your own jumps)?
    ; You've pointed at the target, so go straight to SC Assist.
    if FlagOn(FLAG_SC) {
        Say("Already in supercruise - skipping launch.")
        Sleep 500
    } else {
        if !LaunchAndEnterSupercruise()
            return
    }

    Say("Switching on Supercruise Assist...")
    for name in SCA_SEQUENCE
        Tap(name)
    Tap("Speed75")                          ; blue zone

    Say("SC Assist has the wheel. Make a cup of tea.")
    if !WaitUntil(() => !FlagOn(FLAG_SC), 0)
        return

    Sleep 1000
    ApproachAndDock()
}

; After the drop (or when you've dropped out yourself): full throttle toward the
; station for DOCK_DELAY_SEC, then request docking (with retries).
ApproachAndDock() {
    global Running
    Running := true
    Say("Closing in for " DOCK_DELAY_SEC " s before requesting docking...")
    Tap("Speed100")                         ; the drop leaves throttle at zero - close the gap
    Sleep DOCK_DELAY_SEC * 1000
    if Running
        RequestDocking()
}

; Docked or in normal space: launch if needed, clear mass lock, enter supercruise,
; then wait for you to point at the target and press F9 again.
LaunchAndEnterSupercruise() {
    global AwaitingAlign
    if FlagOn(FLAG_DOCKED) {
        Say("Launching...")
        j := LatestJournal()
        pos := j ? FileGetSize(j) : 0
        for name in LAUNCH_SEQUENCE
            Tap(name)
        if !WaitUntil(() => !FlagOn(FLAG_DOCKED), 180)
            return Running ? Fail("Didn't undock. Check LAUNCH_SEQUENCE lands on Auto Launch.") : ""
        Say("Docking computer flying us out (waits for traffic)...")
        if !WaitForADCHandover(j, &pos)
            return Running ? Fail("Docking computer still flying after " ADC_MAX_SEC " s - you have control.") : ""
    }

    Say("Clearing mass lock...")
    Tap("Speed100")
    Tap("Boost")
    if !WaitUntil(() => !FlagOn(FLAG_MASSLOCK), 90)
        return Running ? Fail("Still mass locked after 90 s.") : ""

    Say("Engaging supercruise...")
    Tap("Supercruise")
    if !WaitUntil(() => FlagOn(FLAG_SC), 30)
        return Running ? Fail("Didn't enter supercruise (target obstructed? FSD cooling?)") : ""
    Sleep 1500
    Tap("Speed0")                           ; idle while you line up
    AwaitingAlign := true
    Say("Point roughly at your target, then press F9 again.")
    return WaitUntil(() => !AwaitingAlign, 0)
}

; Requests docking. If denied for being too far away, flies in at full
; throttle and asks again every RETRY_SEC until granted.
RequestDocking() {
    global Running
    Running := true
    Loop DOCK_TRIES {
        if !Running
            return
        Say("Requesting docking (attempt " A_Index ")...")
        j := LatestJournal()
        pos := j ? FileGetSize(j) : 0

        for name in DOCK_SEQUENCE
            Tap(name)

        result := ""
        start := A_TickCount
        while Running && (A_TickCount - start < 8000) && (result = "") {
            txt := ReadNew(j, &pos)
            if InStr(txt, '"DockingGranted"')
                result := "granted"
            else if RegExMatch(txt, '"DockingDenied".*?"Reason":"(\w+)"', &m)
                result := m[1]
            Sleep 300
        }

        if (result = "granted")
        {
            Tap("Speed0")                   ; ADC only takes over at zero throttle
            return Done("Docking granted. Throttle zeroed - the ADC has it from here.")
        }
        if (result = "Distance") {
            Say("Too far out - closing in, retrying in " RETRY_SEC " s...")
            Tap("Speed100")
            Sleep RETRY_SEC * 1000
            continue
        }
        if (result != "")
            return Fail("Docking denied: " result)
        return Running ? Fail("No docking response. Tune DOCK_SEQUENCE and test with F10.") : ""
    }
    if Running {
        Tap("Speed0")
        Fail("Still too far after " DOCK_TRIES " tries. Throttle set to zero.")
    }
}

Abort() {
    global Running, AwaitingAlign
    Running := false
    AwaitingAlign := false
    if WinActive("ahk_exe EliteDangerous64.exe")
        Tap("Speed0")
    Say("Aborted.", 3000)
}

; ---------- helpers ----------
Tap(name, hold := 100) {
    key := K[name]
    SendSC(key, false)
    Sleep hold
    SendSC(key, true)
    Sleep (SLOW_MODE ? 1000 : 250)
}

; Elite reads raw hardware scan codes (DirectInput), so send those directly
SendSC(key, up) {
    sc := GetKeySC(key)
    flags := 0x8 | (up ? 0x2 : 0) | (sc > 0xFF ? 0x1 : 0)   ; SCANCODE | KEYUP | EXTENDED
    buf := Buffer(40, 0)                                     ; INPUT struct (64-bit)
    NumPut("UInt", 1, buf, 0)                                ; INPUT_KEYBOARD
    NumPut("UShort", sc & 0xFF, buf, 10)                     ; wScan
    NumPut("UInt", flags, buf, 12)                           ; dwFlags
    return DllCall("SendInput", "UInt", 1, "Ptr", buf, "Int", 40)
}

Flags() {
    global LastFlags
    Loop 5 {
        try {
            txt := FileRead(ED_DIR "\Status.json")
            if RegExMatch(txt, '"Flags":(\d+)', &m) {
                LastFlags := Integer(m[1])
                return LastFlags
            }
        }
        Sleep 50
    }
    return LastFlags                        ; file mid-write: use last good reading
}

FlagOn(flag) => (Flags() & flag) != 0

WaitUntil(cond, timeoutSec) {
    start := A_TickCount
    while Running {
        if cond()
            return true
        if timeoutSec && (A_TickCount - start > timeoutSec * 1000)
            return false
        Sleep 250
    }
    return false
}

; Elite logs a "Music" event with track "DockingComputer" while the ADC flies.
; When the track changes to anything else, the ADC has handed control back.
WaitForADCHandover(j, &pos) {
    sawADC := false
    start := A_TickCount
    while Running {
        txt := ReadNew(j, &pos)
        p := 1
        while (p := RegExMatch(txt, '"MusicTrack":"(\w+)"', &m, p)) {
            if (m[1] = "DockingComputer")
                sawADC := true
            else if sawADC
                return true
            p += m.Len
        }
        elapsed := (A_TickCount - start) / 1000
        if (!sawADC && elapsed > 15) {      ; never saw ADC music: fall back to fixed wait
            if (HANDOFF_SEC > 15)
                Sleep (HANDOFF_SEC - 15) * 1000
            return Running
        }
        if (elapsed > ADC_MAX_SEC)
            return false
        Sleep 500
    }
    return false
}

ReadNew(j, &pos) {
    if !j
        return ""
    try {
        if (FileGetSize(j) <= pos)
            return ""
        f := FileOpen(j, "r")
        f.Pos := pos
        txt := f.Read()
        pos := f.Pos
        f.Close()
        return txt
    }
    return ""
}

LatestJournal() {
    newest := "", newestTime := 0
    Loop Files ED_DIR "\Journal.*.log" {
        if (A_LoopFileTimeModified > newestTime) {
            newestTime := A_LoopFileTimeModified
            newest := A_LoopFileFullPath
        }
    }
    return newest
}

; Black box with orange text. Click-through and never takes focus,
; so keypresses keep going to Elite.
Say(msg, ms := 0) {
    global OSD, OSDText
    if !OSD {
        OSD := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        OSD.BackColor := OSD_BG
        OSD.MarginX := 16, OSD.MarginY := 10
        OSD.SetFont("s" OSD_FONT_SIZE " c" OSD_COLOR " bold", OSD_FONT)
        OSDText := OSD.AddText("w" OSD_WIDTH " r2", "")
    }
    OSDText.Value := "ED helper: " msg
    OSD.Show("NoActivate x" OSD_X " y" OSD_Y " AutoSize")
    try WinSetTransparent(OSD_OPACITY, OSD.Hwnd)   ; after Show - a hidden window can't be found
    SetTimer HideOSD, (ms ? -ms : 0)       ; a new message cancels any pending hide
}

HideOSD() {
    global OSD
    if OSD
        OSD.Hide()
}

Done(msg) {
    global Running
    Running := false
    Say(msg, 6000)
}

Fail(msg) {
    global Running
    Running := false
    Say("STOPPED - " msg, 10000)
}
