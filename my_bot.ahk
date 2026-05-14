#Requires AutoHotkey v2.0
#SingleInstance Force

A_CoordModeMouse := "Screen"
A_CoordModePixel := "Screen"

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

WaitForColor(x, y, expectedColor, timeout := 10000) {
    start := A_TickCount
    while (A_TickCount - start < timeout) {
        if (CompareColor(PixelGetColor(x, y), expectedColor, colorTolerance))
            return true
        Sleep(100)
    }
    return false
}

StepFailed(number, reason) {
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
    Sleep(2000)
    return true
}

; ============================================
;  STEP 1 — Dismiss startup news / pop-ups
; ============================================
;  Several pop-ups can stack on launch (news, daily login, calendar...).
;  We press Escape repeatedly until the main menu sentinel pixel is visible.
Step1_DismissNews() {
    global colorTolerance
    mainMenuX     := 100
    mainMenuY     := 100
    mainMenuColor := 0xFFFFFF
    maxAttempts   := 8

    Loop maxAttempts {
        if (CompareColor(PixelGetColor(mainMenuX, mainMenuY), mainMenuColor, colorTolerance))
            return true
        SendKey("{Escape}", 800)
    }

    return false
}

; ============================================
;  STEP 2 — Open "Chargements" shop and buy 4 recurring items
; ============================================
;  1. Find and click the "Chargements" entry on the main menu via ImageSearch
;     (reference image: images/shipments.png).
;  2. For each of the 4 item slots: check the sentinel color (= item is
;     buyable), click the buy button, then click the purchase confirmation.
;     If the sentinel color doesn't match (already bought, locked, ...),
;     skip that slot silently.
Step2_BuyShipments() {
    global colorTolerance

    shipmentsImage := A_ScriptDir "\images\shipments.png"

    ; --- Navigate to the shop ---
    if (!FileExist(shipmentsImage))
        return false

    foundX := 0
    foundY := 0
    try {
        if (!ImageSearch(&foundX, &foundY, 0, 0, A_ScreenWidth, A_ScreenHeight,
                         "*30 " shipmentsImage))
            return false
    } catch {
        return false
    }

    ClickPos(foundX, foundY, 1500)

    ; --- Buy items ---
    ; Each slot: { x, y, color, confirmX, confirmY }
    ;   x, y       = buy button position
    ;   color      = pixel color at (x, y) when the item is available
    ;   confirmX/Y = position of the purchase confirmation button
    ; TODO: capture these values with F1 in-game and fill them in.
    items := [
        { x: 0, y: 0, color: 0x000000, confirmX: 0, confirmY: 0 },
        { x: 0, y: 0, color: 0x000000, confirmX: 0, confirmY: 0 },
        { x: 0, y: 0, color: 0x000000, confirmX: 0, confirmY: 0 },
        { x: 0, y: 0, color: 0x000000, confirmX: 0, confirmY: 0 },
    ]

    for item in items {
        if (item.x = 0)
            continue
        if (!CompareColor(PixelGetColor(item.x, item.y), item.color, colorTolerance))
            continue

        ClickPos(item.x, item.y, 700)
        ClickPos(item.confirmX, item.confirmY, 1000)
    }

    return true
}

; ============================================
;  MAIN SEQUENCE — 8 STEPS
; ============================================
RunSequence() {
    NotifyDiscord("🚀 Starting", "Bot launched, beginning sequence")

    ; --- STEP 0: Launch the game ---
    if (!LaunchGame())
        StepFailed(0, "Unable to launch the game")
    NotifyDiscord("✅ Completed", "Step 0 executed successfully")

    ; --- STEP 1: Dismiss startup news / pop-ups ---
    if (!Step1_DismissNews())
        StepFailed(1, "Main menu not reached after dismissing pop-ups")
    NotifyDiscord("✅ Completed", "Step 1 executed successfully")

    ; --- STEP 2: Open Chargements shop and buy recurring items ---
    if (!Step2_BuyShipments())
        StepFailed(2, "Could not open Chargements or shipments.png not found")
    NotifyDiscord("✅ Completed", "Step 2 executed successfully")

    ExitApp()
}
