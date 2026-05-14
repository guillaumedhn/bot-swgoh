#Requires AutoHotkey v2.0
#SingleInstance Force

A_CoordModeMouse := "Screen"
A_CoordModePixel := "Screen"

; ============================================
;  CONFIGURATION
; ============================================
cheminJeu        := "C:\Chemin\Complet\Vers\TonJeu.exe"
titreFenetre     := "ahk_exe TonJeu.exe"
webhookUrl       := "TON_WEBHOOK_DISCORD"
timeoutLancement := 60        ; secondes max pour charger le jeu
toleranceCouleur := 15
modeAuto         := false     ; true = lance auto au démarrage du script

; ============================================
;  RACCOURCIS
; ============================================
F1::OutilDebug()
F6::LancerSequence()
F7::ArretUrgence()

; Mode auto : déclenchement immédiat (utile pour controller.py et planificateur)
if (modeAuto || A_Args.Length > 0) {
    Sleep(1000)
    LancerSequence()
}

; ============================================
;  OUTIL DEBUG (F1 = relevé position + couleur)
; ============================================
OutilDebug() {
    MouseGetPos(&x, &y)
    couleur := PixelGetColor(x, y)
    info := "Position: x:" x " y:" y "`nCouleur: " couleur
    A_Clipboard := "x:" x " y:" y " couleur:" couleur
    ToolTip(info "`n(copié)")
    SetTimer(() => ToolTip(), -3000)
}

; ============================================
;  ARRÊT D'URGENCE
; ============================================
ArretUrgence() {
    NotifierDiscord("🛑 Arrêt manuel", "Bot stoppé par l'utilisateur (F7)", 0xef4444)
    ExitApp()
}

; ============================================
;  HELPERS
; ============================================
NotifierDiscord(titre, message, couleur := 0x22c55e) {
    global webhookUrl
    if (webhookUrl = "TON_WEBHOOK_DISCORD")
        return

    json := '{"embeds":[{"title":"' titre '","description":"' message '","color":' couleur '}]}'
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.Open("POST", webhookUrl, true)
        http.SetRequestHeader("Content-Type", "application/json")
        http.Send(json)
    }
}

ClicPos(x, y, pause := 300) {
    Click(x, y)
    Sleep(pause)
}

EnvoyerTouche(touche, pause := 300) {
    Send(touche)
    Sleep(pause)
}

ComparerCouleur(c1, c2, tol := 15) {
    r1 := (c1 >> 16) & 0xFF, g1 := (c1 >> 8) & 0xFF, b1 := c1 & 0xFF
    r2 := (c2 >> 16) & 0xFF, g2 := (c2 >> 8) & 0xFF, b2 := c2 & 0xFF
    return (Abs(r1-r2) <= tol && Abs(g1-g2) <= tol && Abs(b1-b2) <= tol)
}

AttendreCouleur(x, y, couleurAttendue, timeout := 10000) {
    debut := A_TickCount
    while (A_TickCount - debut < timeout) {
        if (ComparerCouleur(PixelGetColor(x, y), couleurAttendue, toleranceCouleur))
            return true
        Sleep(100)
    }
    return false
}

EchecEtape(numero, raison) {
    NotifierDiscord("❌ Échec étape " numero, raison, 0xef4444)
    ExitApp()
}

; ============================================
;  LANCEMENT DU JEU
; ============================================
LancerJeu() {
    global cheminJeu, titreFenetre, timeoutLancement

    if (WinExist(titreFenetre)) {
        WinActivate(titreFenetre)
        Sleep(1000)
        return true
    }

    try {
        Run(cheminJeu)
    } catch {
        return false
    }

    if (!WinWait(titreFenetre, , timeoutLancement))
        return false

    WinActivate(titreFenetre)
    WinWaitActive(titreFenetre, , 5)
    Sleep(2000)
    return true
}

; ============================================
;  SÉQUENCE PRINCIPALE — 8 ÉTAPES
; ============================================
LancerSequence() {
    NotifierDiscord("🚀 Démarrage", "Bot lancé, début de la séquence")

    ; --- ÉTAPE 0 : Lancer le jeu ---
    if (!LancerJeu())
        EchecEtape(0, "Impossible de lancer le jeu")

    NotifierDiscord("✅ Terminé", "L'etape 0 a été exécutée avec succès")
    ExitApp()
}