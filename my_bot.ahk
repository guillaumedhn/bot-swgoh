#Requires AutoHotkey v2.0
#SingleInstance Force

A_CoordModeMouse := "Screen"
A_CoordModePixel := "Screen"

; Per-monitor DPI awareness. Without this, AHK reads coords from the unscaled
; buffer, which breaks when Windows display scaling != 100% or when the game
; window moves across monitors with different DPI.
try DllCall("SetThreadDpiAwarenessContext", "ptr", -3, "ptr")

; ============================================
;  LOAD CONFIG FROM .env
; ============================================
envFile := A_ScriptDir "\my_bot.env"

if (!FileExist(envFile)) {
    MsgBox(
        "Config file not found:`n" envFile
        "`n`nCopy my_bot.env.example to my_bot.env and fill it in.",
        "Config error", "Icon!")
    ExitApp()
}

config := LoadEnv(envFile)

gamePath        := config.Get("GAME_PATH", "")
windowTitle     := config.Get("WINDOW_TITLE", "")
webhookUrl      := config.Get("WEBHOOK_URL", "")
launchTimeout   := Integer(config.Get("LAUNCH_TIMEOUT", "60"))
colorTolerance  := Integer(config.Get("COLOR_TOLERANCE", "15"))
autoMode        := (config.Get("AUTO_MODE", "false") = "true")

; Basic checks
if (gamePath = "" || windowTitle = "") {
    MsgBox("GAME_PATH or WINDOW_TITLE missing in my_bot.env", "Error", "Icon!")
    ExitApp()
}

; ============================================
;  .env READER
; ============================================
LoadEnv(path) {
    result := Map()
    content := FileRead(path, "UTF-8")

    for line in StrSplit(content, "`n", "`r") {
        line := Trim(line)

        ; Skip empty lines and comments
        if (line = "" || SubStr(line, 1, 1) = "#")
            continue

        ; Split KEY=VALUE at the first =
        pos := InStr(line, "=")
        if (pos = 0)
            continue

        key := Trim(SubStr(line, 1, pos - 1))
        value := Trim(SubStr(line, pos + 1))

        ; Strip surrounding quotes if present
        if ((SubStr(value, 1, 1) = '"' && SubStr(value, -1) = '"')
         || (SubStr(value, 1, 1) = "'" && SubStr(value, -1) = "'"))
            value := SubStr(value, 2, StrLen(value) - 2)

        result[key] := value
    }

    return result
}

; ============================================
;  HOTKEYS
; ============================================
F1::DebugTool()
F6::RunSequence()
F4::TestNotification()
F7::EmergencyStop()

; Auto mode: trigger immediately (useful for controller.py and scheduler)
if (autoMode || A_Args.Length > 0) {
    Sleep(1000)
    RunSequence()
}

; ============================================
;  DEBUG TOOL (F1 = capture position + color)
; ============================================
DebugTool() {
    MouseGetPos(&x, &y)
    color := PixelGetColor(x, y)
    info := "Position: x:" x " y:" y "`nColor: " color
    A_Clipboard := "x:" x " y:" y " color:" color
    ToolTip(info "`n(copied)")
    SetTimer(() => ToolTip(), -3000)
}

; ============================================
;  EMERGENCY STOP
; ============================================
EmergencyStop() {
    NotifyDiscord("🛑 Manual stop", "Bot stopped by user (F7)", 0xef4444)
    ExitApp()
}

; ============================================
;  TEST NOTIFICATION
; ============================================
TestNotification() {
    NotifyDiscord("🧪 Test", "This message comes from my AHK bot")
    ToolTip("Notification sent")
    SetTimer(() => ToolTip(), -2000)
}

; ============================================
;  HELPERS
; ============================================
NotifyDiscord(title, message, color := 0x22c55e) {
    global webhookUrl
    if (webhookUrl = "") {
        ToolTip("⚠ WEBHOOK_URL is empty in my_bot.env")
        SetTimer(() => ToolTip(), -3000)
        return
    }

    json := '{"embeds":[{"title":"' title '","description":"' message '","color":' color '}]}'
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.Open("POST", webhookUrl, false)   ; false = synchronous
        http.SetRequestHeader("Content-Type", "application/json")
        http.Send(json)
        if (http.Status < 200 || http.Status >= 300) {
            ToolTip("Discord error " http.Status ": " http.ResponseText)
            SetTimer(() => ToolTip(), -4000)
        }
    } catch Error as e {
        ToolTip("Discord exception: " e.Message)
        SetTimer(() => ToolTip(), -4000)
    }
}

ClickPos(x, y, pause := 300) {
    Click(x, y)
    Sleep(pause)
}

SendKey(key, pause := 300) {
    Send(key)
    Sleep(pause)
}

CompareColor(c1, c2, tol := 15) {
    r1 := (c1 >> 16) & 0xFF, g1 := (c1 >> 8) & 0xFF, b1 := c1 & 0xFF
    r2 := (c2 >> 16) & 0xFF, g2 := (c2 >> 8) & 0xFF, b2 := c2 & 0xFF
    return (Abs(r1-r2) <= tol && Abs(g1-g2) <= tol && Abs(b1-b2) <= tol)
}

;  Optional jitterIntervalMs: every N ms, nudge the mouse by 1px and back.
;  Defeats the in-game "Are you still here?" idle dialog during long waits.
WaitForColor(x, y, expectedColor, timeout := 10000, jitterIntervalMs := 0) {
    start := A_TickCount
    lastJitter := A_TickCount
    while (A_TickCount - start < timeout) {
        if (CompareColor(PixelGetColor(x, y), expectedColor, colorTolerance))
            return true

        if (jitterIntervalMs > 0 && A_TickCount - lastJitter >= jitterIntervalMs) {
            MouseGetPos(&mx, &my)
            MouseMove(mx + 1, my + 1, 0)
            Sleep(50)
            MouseMove(mx, my, 0)
            lastJitter := A_TickCount
        }

        Sleep(100)
    }
    return false
}

;  Poll the screen for an image (relative path under the script dir) until it's
;  found or the timeout elapses. On success, fills foundX/foundY with the match
;  coordinates and returns true. Optional bounding box: (x1, y1) to (x2, y2);
;  pass 0 for x2/y2 to default to the full screen.
WaitForImage(imageRelPath, &foundX, &foundY, timeout := 5000, x1 := 0, y1 := 0, x2 := 0, y2 := 0) {
    fullPath := A_ScriptDir "\" imageRelPath
    if (!FileExist(fullPath))
        return false

    if (x2 = 0)
        x2 := A_ScreenWidth
    if (y2 = 0)
        y2 := A_ScreenHeight

    start := A_TickCount
    while (A_TickCount - start < timeout) {
        try {
            if (ImageSearch(&foundX, &foundY, x1, y1, x2, y2, "*30 " fullPath))
                return true
        }
        Sleep(150)
    }
    return false
}

;  Convenience wrapper: wait for an image (optionally inside an area), click
;  the match, pause afterwards.
WaitForAndClickImage(imageRelPath, timeout := 5000, pauseAfter := 500, x1 := 0, y1 := 0, x2 := 0, y2 := 0) {
    foundX := 0
    foundY := 0
    if (!WaitForImage(imageRelPath, &foundX, &foundY, timeout, x1, y1, x2, y2))
        return false
    ClickPos(foundX, foundY, pauseAfter)
    return true
}

;  Capture the full virtual screen (all monitors) to a PNG via PowerShell.
;  Best-effort: failures are swallowed so StepFailed can always send a fallback
;  text notification.
SaveScreenshot(filepath) {
    psCmd := "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; "
           . "$b = [System.Windows.Forms.SystemInformation]::VirtualScreen; "
           . "$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; "
           . "$g = [System.Drawing.Graphics]::FromImage($bmp); "
           . "$g.CopyFromScreen($b.X, $b.Y, 0, 0, $b.Size); "
           . "$bmp.Save('" filepath "'); "
           . "$bmp.Dispose(); $g.Dispose()"

    try RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "' psCmd '"', , "Hide")
}

;  Post a Discord embed with an attached file via curl.exe (multipart upload).
;  curl.exe ships with Windows 10 1803+; no external deps needed.
NotifyDiscordWithFile(filepath, title, message, color := 0xef4444) {
    global webhookUrl
    if (webhookUrl = "" || !FileExist(filepath))
        return false

    payload := '{"embeds":[{"title":"' title '","description":"' message '","color":' color '}]}'
    tempJson := A_Temp "\bot_discord_payload.json"
    try FileDelete(tempJson)
    FileAppend(payload, tempJson, "UTF-8")

    cmd := 'curl.exe -s -X POST '
         . '-F "payload_json=<' tempJson '" '
         . '-F "file=@' filepath '" '
         . '"' webhookUrl '"'

    try RunWait(cmd, , "Hide")
    try FileDelete(tempJson)
    return true
}

StepFailed(number, reason) {
    ; Capture a screenshot so we can see what was on screen at failure time.
    logsDir := A_ScriptDir "\logs"
    if (!DirExist(logsDir))
        DirCreate(logsDir)

    timestamp := FormatTime(, "yyyyMMdd_HHmmss")
    screenshotPath := logsDir "\step" number "_" timestamp ".png"

    SaveScreenshot(screenshotPath)

    sent := false
    if (FileExist(screenshotPath))
        sent := NotifyDiscordWithFile(screenshotPath, "❌ Step " number " failed", reason, 0xef4444)

    if (!sent)
        NotifyDiscord("❌ Step " number " failed", reason, 0xef4444)

    ExitApp()
}

; ============================================
;  GAME LAUNCH
; ============================================
LaunchGame() {
    global gamePath, windowTitle, launchTimeout

    if (WinExist(windowTitle)) {
        WinActivate(windowTitle)
        Sleep(1000)
        return true
    }

    try {
        Run(gamePath)
    } catch {
        return false
    }

    if (!WinWait(windowTitle, , launchTimeout))
        return false

    WinActivate(windowTitle)
    WinWaitActive(windowTitle, , 5)
    Sleep(16000)
    return true
}

; ============================================
;  STEP 1 — Dismiss startup news / pop-ups + claim daily login rewards
; ============================================
;  Several pop-ups can stack on launch (news, daily login, calendar...).
;  Best-effort, never fails: Step 2's ImageSearch is the real test of
;  whether we successfully reached the main menu.
;
;  Daily login rewards: multiple "get" buttons may appear in sequence
;  (one per available reward). Loop on images/get.png around the known
;  button position, clicking each match and pausing between tries so the
;  next reward popup has time to render.
Step1_DismissNews() {
    getBtnX        := 2294
    getBtnY        := 975
    getImage       := "images\get.png"
    searchRadius   := 80
    maxGetAttempts := 10
    retryPause     := 3000

    Loop maxGetAttempts {
        if (!WaitForAndClickImage(getImage, 1500, 500,
                                  getBtnX - searchRadius, getBtnY - searchRadius,
                                  getBtnX + searchRadius, getBtnY + searchRadius))
            break
        Sleep(retryPause)
    }

    ; --- Dismiss any remaining popups (close button or Escape) ---
    ;  Multiple news panels can stack; keep looking for close.png and
    ;  clicking it. After a few empty passes (no close button visible),
    ;  fall back to Escape and finally exit.
    closeBtnX         := 2505
    closeBtnY         := 372
    closeImage        := "images\close.png"
    maxCloseAttempts  := 20
    maxConsecutiveMiss := 3
    consecutiveMiss   := 0

    Loop maxCloseAttempts {
        if (WaitForAndClickImage(closeImage, 800, 500,
                                 closeBtnX - searchRadius, closeBtnY - searchRadius,
                                 closeBtnX + searchRadius, closeBtnY + searchRadius)) {
            consecutiveMiss := 0
            Sleep(retryPause)
            continue
        }

        consecutiveMiss += 1
        if (consecutiveMiss >= maxConsecutiveMiss)
            break
        SendKey("{Escape}", retryPause)
    }
}

; ============================================
;  STEP 2 — Open "Chargements" shop and buy 4 recurring items
; ============================================
;  1. Verify the "Chargements" navigation icon by its sentinel color, then
;     click it.
;  2. For each of the 4 item slots: ImageSearch for the shared money.png
;     inside a small box around the slot's known position. If found → click
;     → wait for confirm.png → click confirm. If the price icon isn't there
;     (already bought, locked, ...), skip silently.
;
;  Reference images (place under images/ in the script dir):
;    - images/money.png   : the price/buy icon shared by all 4 slots
;    - images/confirm.png : the shared purchase confirmation button
Step2_BuyShipments() {
    global colorTolerance

    ; --- Shipments navigation entry on the main menu ---
    shipmentsX     := 1365
    shipmentsY     := 394
    shipmentsColor := 0xFFFFFF

    if (!CompareColor(PixelGetColor(shipmentsX, shipmentsY), shipmentsColor, colorTolerance))
        return "Shipments nav icon not found on main menu (color mismatch)"

    ClickPos(shipmentsX, shipmentsY, 1500)
    Sleep(Random(1000, 2000))

    ; --- Buy items ---
    ; The 4 slots where money.png is expected to appear when the item is buyable.
    itemPositions := [
        { x: 1437, y: 849 },
        { x: 713,  y: 849 },
        { x: 1070, y: 859 },
        { x: 2888, y: 497 },
    ]
    itemImage    := "images\money.png"
    searchRadius := 60

    ; The confirm popup shows the same money icon next to the confirm button,
    ; so we ImageSearch money.png around the confirm position too.
    confirmX := 1819
    confirmY := 909

    for pos in itemPositions {
        if (!WaitForAndClickImage(itemImage, 2000, 700,
                                  pos.x - searchRadius, pos.y - searchRadius,
                                  pos.x + searchRadius, pos.y + searchRadius))
            continue
        Sleep(Random(1000, 2000))

        WaitForAndClickImage(itemImage, 3000, 1000,
                             confirmX - searchRadius, confirmY - searchRadius,
                             confirmX + searchRadius, confirmY + searchRadius)
        Sleep(Random(1500, 2000))
    }

    SendKey("{Escape}", 1000)
    Sleep(Random(1000, 2000))
    return ""
}

; ============================================
;  STEP 3 — Open SHOP and claim the daily free reward
; ============================================
;  1. Return to the main menu (Escape), then ImageSearch for the SHOP
;     navigation icon and click it.
;  2. ImageSearch for free.png around the known reward button position
;     and click it to claim the daily free reward.
;
;  Reference images:
;    - images/shop.png : the SHOP navigation icon on the main menu
;    - images/free.png : the daily free reward button inside the shop
Step3_GetFreeReward() {
    shopImage := "images\shop.png"
    freeImage := "images\free.png"

    ; --- Back to main menu, then open Shop ---
    SendKey("{Escape}", 1000)
    Sleep(Random(1000, 2000))

    if (!WaitForAndClickImage(shopImage, 5000, 2000))
        return "Shop nav icon not found on main menu"
    Sleep(Random(1000, 2000))

    ; --- Claim the daily free reward ---
    freeBtnX     := 668
    freeBtnY     := 781
    searchRadius := 80

    if (!WaitForAndClickImage(freeImage, 4000, 1500,
                              freeBtnX - searchRadius, freeBtnY - searchRadius,
                              freeBtnX + searchRadius, freeBtnY + searchRadius))
        return "Daily free reward button not found in Shop"
    Sleep(Random(1000, 2000))

    SendKey("{Escape}", 1000)
    Sleep(Random(1000, 2000))
    return ""
}

; ============================================
;  STEP 4 — Fleet Arena: auto-battle the default opponent
; ============================================
;  1. Open the Arena nav icon from the main menu.
;  2. Click "Participate" → "Battle" (default top opponent) → "Fight".
;  3. Enable auto-battle once the fight starts.
;  4. Poll the defeat banner pixel until it turns red, then tap a random
;     spot around that position to dismiss the result screen.
;
;  Reference images:
;    - images/arena.png         : Arena nav icon on the main menu
;    - images/participate.png   : "Participate" entry button
;    - images/battle.png        : "Battle" challenge button (default opponent)
;    - images/fight.png         : "Fight" deploy/start button
;    - images/auto-toggle.png   : Auto-battle toggle inside the battle UI
Step4_FleetArena() {
    arenaImage       := "images\arena.png"
    participateImage := "images\participate.png"
    battleImage      := "images\battle.png"
    fightImage       := "images\fight.png"
    autoImage        := "images\auto-toggle.png"

    searchRadius := 80

    ; --- 1. Open Arena ---
    arenaX := 901, arenaY := 692
    if (!WaitForAndClickImage(arenaImage, 5000, 2000,
                              arenaX - searchRadius, arenaY - searchRadius,
                              arenaX + searchRadius, arenaY + searchRadius))
        return "Arena nav icon not found on main menu"
    Sleep(Random(1000, 2000))

    ; --- 2. Participate ---
    participateX := 1707, participateY := 1057
    if (!WaitForAndClickImage(participateImage, 5000, 1500,
                              participateX - searchRadius, participateY - searchRadius,
                              participateX + searchRadius, participateY + searchRadius))
        return "'Participate' button not found in Arena"
    Sleep(Random(1000, 2000))

    ; --- 3. Battle (default top opponent) ---
    battleX := 1683, battleY := 1091
    if (!WaitForAndClickImage(battleImage, 5000, 1500,
                              battleX - searchRadius, battleY - searchRadius,
                              battleX + searchRadius, battleY + searchRadius))
        return "'Battle' button not found (default opponent)"
    Sleep(Random(1000, 2000))

    ; --- 4. Fight (deploy + start) ---
    fightX := 2930, fightY := 1373
    if (!WaitForAndClickImage(fightImage, 8000, 2000,
                              fightX - searchRadius, fightY - searchRadius,
                              fightX + searchRadius, fightY + searchRadius))
        return "'Fight' button not found"
    Sleep(Random(1000, 2000))

    ; --- 5. Enable auto-battle if needed ---
    ;  images/auto-toggle.png captures the toggle in its OFF state (no green
    ;  indicator). If we find it, auto is off → click to enable. If we don't
    ;  find it, auto is already on → skip and let the battle resolve.
    autoX := 254, autoY := 59
    if (WaitForAndClickImage(autoImage, 8000, 1500,
                             autoX - searchRadius, autoY - searchRadius,
                             autoX + searchRadius, autoY + searchRadius))
        Sleep(Random(1000, 2000))

    ; --- 6. Wait for the defeat banner pixel to turn red (up to 4 min) ---
    ;  If the banner never shows (victory, disconnect, slow fight...), fall
    ;  through anyway — a tap around the banner position is harmless and
    ;  nudges whatever result/continue screen is showing.
    defeatX     := 1738
    defeatY     := 712
    defeatColor := 0xA52222
    ; Jitter the mouse every 3 min during the wait so the game's idle dialog
    ; ("Are you still here?") doesn't fire mid-battle.
    WaitForColor(defeatX, defeatY, defeatColor, 240000, 180000)

    ; --- 7. Random tap around the defeat banner to dismiss the result ---
    Sleep(Random(1000, 2000))
    ClickPos(defeatX + Random(-100, 100), defeatY + Random(-60, 60), 1000)
    Sleep(Random(1000, 2000))

    return ""
}

; ============================================
;  MAIN SEQUENCE — 8 STEPS
; ============================================
RunSequence() {
    NotifyDiscord("🚀 Starting", "Bot launched, beginning sequence")

    ; --- STEP 0: Launch the game ---
    ;  No screenshot/Discord report here: if the game won't launch there's
    ;  nothing useful on screen, so just kill the script.
    if (!LaunchGame())
        ExitApp()
    NotifyDiscord("✅ Completed", "Step 0 - Launch the game executed successfully")

    ; --- STEP 1: Dismiss startup news / pop-ups + claim daily login rewards ---
    Step1_DismissNews()
    NotifyDiscord("✅ Completed", "Step 1 - Dismiss startup news and claim daily login rewards executed successfully")

    ; --- STEP 2: Open Shipments shop and buy recurring items ---
    ;  Step functions return "" on success, or a specific reason string
    ;  naming the sub-task that failed.
    reason := Step2_BuyShipments()
    if (reason != "")
        StepFailed(2, reason)
    NotifyDiscord("✅ Completed", "Step 2 - Buy Chargements shop recurring items executed successfully")

    ; --- STEP 3: Open Shop and claim the daily free reward ---
    reason := Step3_GetFreeReward()
    if (reason != "")
        StepFailed(3, reason)
    NotifyDiscord("✅ Completed", "Step 3 - Claim daily free reward from Shop executed successfully")

    ; --- STEP 4: Fleet Arena auto-battle ---
    reason := Step4_FleetArena()
    if (reason != "")
        StepFailed(4, reason)
    NotifyDiscord("✅ Completed", "Step 4 - Fleet Arena auto-battle executed successfully")

    ExitApp()
}
