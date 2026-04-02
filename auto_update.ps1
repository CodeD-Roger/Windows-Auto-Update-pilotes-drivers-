# ============================================================
#  auto_update.ps1
#  Mise a jour automatique : Windows Update + Pilotes
#  - Silencieux (tourne en arriere-plan)
#  - Pas de redemarrage automatique
#  - Les mises a jour s'appliquent au prochain redemarrage
# ============================================================

# ── Verification des droits admin ──────────────────────────
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Exit 1
}

# ── Installation du module PSWindowsUpdate si absent ───────
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Install-PackageProvider -Name NuGet -Force -Scope AllUsers | Out-Null
    Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -SkipPublisherCheck | Out-Null
}

Import-Module PSWindowsUpdate -Force

# ── Windows Update (OS + securite + pilotes) ───────────────
# /AutoReboot:$false = jamais de redemarrage automatique
# /AcceptAll        = accepte toutes les mises a jour sans confirmation
# /Install          = telecharge et installe directement
Get-WindowsUpdate `
    -AcceptAll `
    -Install `
    -AutoReboot:$false `
    -MicrosoftUpdate `
    -NotCategory "Language packs" `
    | Out-Null

# ── Pilotes via Windows Update (categorie Drivers) ─────────
Get-WindowsUpdate `
    -AcceptAll `
    -Install `
    -AutoReboot:$false `
    -Category "Drivers" `
    | Out-Null

# ── Notification Windows a la fin ──────────────────────────
Add-Type -AssemblyName System.Windows.Forms

$notification = New-Object System.Windows.Forms.NotifyIcon
$notification.Icon = [System.Drawing.SystemIcons]::Information
$notification.Visible = $true
$notification.BalloonTipTitle = "Mises a jour terminees"
$notification.BalloonTipText  = "Windows et les pilotes ont ete mis a jour. Les changements seront appliques au prochain redemarrage."
$notification.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
$notification.ShowBalloonTip(8000)

Start-Sleep -Seconds 9
$notification.Dispose()