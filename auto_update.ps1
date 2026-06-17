# ============================================================
#  auto_update.ps1
#  Mise a jour automatique : Windows Update + Pilotes
#  - Silencieux (tourne en arriere-plan)
#  - Pas de redemarrage automatique
#  - Les mises a jour s'appliquent au prochain redemarrage
#
#  Parametres :
#    -RegisterStartup    Cree une tache planifiee qui lance ce
#                        script a chaque demarrage du PC, puis quitte.
#    -UnregisterStartup  Supprime cette tache planifiee, puis quitte.
#
#  Exemples :
#    .\auto_update.ps1                     # execution immediate
#    .\auto_update.ps1 -RegisterStartup    # activer au demarrage
#    .\auto_update.ps1 -UnregisterStartup  # desactiver au demarrage
# ============================================================

param(
    [switch]$RegisterStartup,
    [switch]$UnregisterStartup
)

# ── Verification des droits admin ──────────────────────────
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Warning "Ce script doit etre lance en tant qu'Administrateur."
    Exit 1
}

# ── Nom de la tache planifiee (auto-demarrage) ─────────────
$TaskName = "AutoWindowsUpdate-AtStartup"

# ── Activer le lancement au demarrage ──────────────────────
if ($RegisterStartup) {
    $scriptPath = $MyInvocation.MyCommand.Path

    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""

    # Declenchement a chaque demarrage, avec 2 min de delai
    # pour ne pas ralentir l'ouverture de session.
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = "PT2M"

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable

    # Compte SYSTEM = droits admin, sans ouverture de session requise.
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
        -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName `
        -Action $action -Trigger $trigger -Settings $settings `
        -Principal $principal -Force | Out-Null

    Write-Host "Tache '$TaskName' creee : le script se lancera a chaque demarrage."
    Exit 0
}

# ── Desactiver le lancement au demarrage ───────────────────
if ($UnregisterStartup) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Tache '$TaskName' supprimee : plus de lancement au demarrage."
    } else {
        Write-Host "Aucune tache '$TaskName' trouvee."
    }
    Exit 0
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
Write-Host "Recherche et installation des mises a jour Windows..." -ForegroundColor Cyan
$resultWindows = Get-WindowsUpdate `
    -AcceptAll `
    -Install `
    -AutoReboot:$false `
    -MicrosoftUpdate `
    -NotCategory "Language packs"

# ── Pilotes via Windows Update (categorie Drivers) ─────────
Write-Host "Recherche et installation des pilotes..." -ForegroundColor Cyan
$resultDrivers = Get-WindowsUpdate `
    -AcceptAll `
    -Install `
    -AutoReboot:$false `
    -Category "Drivers"

# ── Resume de ce qui a ete installe ────────────────────────
$allResults = @($resultWindows) + @($resultDrivers) | Where-Object { $_ }

Write-Host ""
Write-Host "================ RESUME ================" -ForegroundColor Yellow

if ($allResults.Count -eq 0) {
    Write-Host "Aucune mise a jour n'etait disponible. Le systeme est deja a jour." -ForegroundColor Green
} else {
    Write-Host "$($allResults.Count) element(s) traite(s) :" -ForegroundColor Green
    Write-Host ""
    $allResults |
        Select-Object @{N='Resultat'; E={ $_.Result }},
                      @{N='KB';       E={ $_.KB }},
                      @{N='Taille';   E={ $_.Size }},
                      @{N='Titre';    E={ $_.Title }} |
        Format-Table -AutoSize -Wrap | Out-Host

    # Indique si un redemarrage est necessaire pour finaliser
    if (Get-WURebootStatus -Silent) {
        Write-Host "Un redemarrage est necessaire pour finaliser les mises a jour." -ForegroundColor Yellow
    }
}
Write-Host "=======================================" -ForegroundColor Yellow
Write-Host ""

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