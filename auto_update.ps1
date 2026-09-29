# ============================================================
#  auto_update.ps1
#  Mise a jour automatique : Windows Update + Pilotes
#  - Silencieux (tourne en arriere-plan)
#  - Pas de redemarrage automatique
#  - Les mises a jour s'appliquent au prochain REDEMARRAGE
#    (avec le demarrage rapide, "Arreter" ne suffit pas)
#  - Journal de chaque execution dans
#    C:\ProgramData\AutoWindowsUpdate\logs\
#
#  Parametres :
#    -RegisterStartup    Installe le script dans Program Files et
#                        cree une tache planifiee (au demarrage +
#                        chaque jour a 12:00), puis quitte.
#    -UnregisterStartup  Supprime cette tache et la copie installee,
#                        puis quitte.
#
#  Exemples :
#    .\auto_update.ps1                     # execution immediate
#    .\auto_update.ps1 -RegisterStartup    # activer l'automatisme
#    .\auto_update.ps1 -UnregisterStartup  # desactiver l'automatisme
# ============================================================

param(
    [switch]$RegisterStartup,
    [switch]$UnregisterStartup
)

# Toute erreur arrete l'etape en cours et remonte au bloc catch.
$ErrorActionPreference = 'Stop'

# ── Verification des droits admin ──────────────────────────
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Warning "Ce script doit etre lance en tant qu'Administrateur."
    Exit 1
}

# ── Emplacements ───────────────────────────────────────────
$TaskName   = "AutoWindowsUpdate-AtStartup"
# Program Files : seuls les administrateurs peuvent y ecrire. La tache
# tourne en SYSTEM ; si elle lancait une copie modifiable par un simple
# utilisateur (Telechargements, Bureau...), cet utilisateur pourrait y
# glisser ses propres commandes et les faire executer en SYSTEM.
$InstallDir = Join-Path $env:ProgramFiles "AutoWindowsUpdate"
$Installed  = Join-Path $InstallDir "auto_update.ps1"
$LogDir     = Join-Path $env:ProgramData "AutoWindowsUpdate\logs"
$KeepLogs   = 30

# ── Activer le lancement automatique ───────────────────────
if ($RegisterStartup) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $source = $MyInvocation.MyCommand.Path
    if ($source -ne $Installed) {
        Copy-Item -LiteralPath $source -Destination $Installed -Force
    }

    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
        -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Installed`""

    # Deux declencheurs :
    #  - au demarrage, avec 2 min de delai pour ne pas ralentir
    #    l'ouverture de session ;
    #  - chaque jour a 12:00. Avec le demarrage rapide (actif par
    #    defaut), "Arreter" puis rallumer n'est pas un demarrage :
    #    sans ce second declencheur, un portable qu'on eteint le soir
    #    pourrait ne jamais lancer la tache.
    $atStartup = New-ScheduledTaskTrigger -AtStartup
    $atStartup.Delay = "PT2M"
    $daily = New-ScheduledTaskTrigger -Daily -At "12:00"

    # StartWhenAvailable : si le PC etait eteint a 12:00, la tache
    # tourne des qu'il est rallume. Une seule execution a la fois,
    # deux heures maximum, et seulement avec un reseau disponible.
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2)

    # Compte SYSTEM = droits admin, sans ouverture de session requise.
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
        -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName `
        -Action $action -Trigger @($atStartup, $daily) -Settings $settings `
        -Principal $principal -Force | Out-Null

    Write-Host "Script installe dans : $Installed"
    Write-Host "Tache '$TaskName' creee : au demarrage et chaque jour a 12:00."
    Write-Host "Journaux : $LogDir"
    Exit 0
}

# ── Desactiver le lancement automatique ────────────────────
if ($UnregisterStartup) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Tache '$TaskName' supprimee."
    } else {
        Write-Host "Aucune tache '$TaskName' trouvee."
    }
    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
        Write-Host "Copie installee supprimee : $InstallDir"
    }
    Write-Host "Les journaux sont conserves : $LogDir"
    Exit 0
}

# ── Journal ────────────────────────────────────────────────
# En tache planifiee, la fenetre est cachee : sans journal, rien ne
# dit ce qui a ete installe, ni si l'execution a echoue.
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Get-ChildItem -LiteralPath $LogDir -Filter "auto_update_*.log" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip ($KeepLogs - 1) |
    Remove-Item -Force
$LogFile = Join-Path $LogDir ("auto_update_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))
Start-Transcript -LiteralPath $LogFile | Out-Null

# ── Notification ───────────────────────────────────────────
# Lance par un utilisateur : bulle dans la zone de notification.
# Lance par la tache (SYSTEM, session 0) : une bulle y serait
# invisible ; on envoie un message a toutes les sessions ouvertes
# avec msg.exe (absent des editions Famille : le journal fait foi).
function Send-Notice([string]$Title, [string]$Text) {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $msg = Join-Path $env:SystemRoot "System32\msg.exe"
        if (Test-Path -LiteralPath $msg) {
            & $msg '*' '/TIME:3600' "$Title - $Text"
        } else {
            Write-Host "Notification impossible (msg.exe absent) : $Title - $Text"
        }
        return
    }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $notification = New-Object System.Windows.Forms.NotifyIcon
    $notification.Icon = [System.Drawing.SystemIcons]::Information
    $notification.Visible = $true
    $notification.BalloonTipTitle = $Title
    $notification.BalloonTipText  = $Text
    $notification.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
    $notification.ShowBalloonTip(8000)
    Start-Sleep -Seconds 9
    $notification.Dispose()
}

$exitCode = 0
try {
    # ── Installation du module PSWindowsUpdate si absent ───
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        # PowerShell 5.1 ne propose pas toujours TLS 1.2 par defaut :
        # sans lui, le telechargement de NuGet echoue.
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        Install-Module -Name PSWindowsUpdate -Repository PSGallery -Force -Scope AllUsers | Out-Null
    }
    Import-Module PSWindowsUpdate -Force

    # ── Windows Update : systeme, securite, produits Microsoft ─
    # -IgnoreReboot : ne jamais redemarrer, et ne jamais POSER la
    #                 question. Sans lui, le module demande s'il faut
    #                 redemarrer : dans une tache cachee, personne ne
    #                 repond et le script reste bloque.
    # -AcceptAll    : accepte toutes les mises a jour sans confirmation
    # -Install      : telecharge et installe directement
    Write-Host "Recherche et installation des mises a jour Windows..." -ForegroundColor Cyan
    $resultWindows = @(Get-WindowsUpdate `
        -MicrosoftUpdate `
        -UpdateType Software `
        -NotCategory "Language packs" `
        -AcceptAll -Install -IgnoreReboot | Where-Object { $_ })

    # ── Pilotes, publies par les fabricants via Windows Update ─
    Write-Host "Recherche et installation des pilotes..." -ForegroundColor Cyan
    $resultDrivers = @(Get-WindowsUpdate `
        -MicrosoftUpdate `
        -UpdateType Driver `
        -AcceptAll -Install -IgnoreReboot | Where-Object { $_ })

    # ── Resume de ce qui a ete installe ────────────────────
    $allResults = $resultWindows + $resultDrivers
    $rebootNeeded = [bool](Get-WURebootStatus -Silent)

    Write-Host ""
    Write-Host "================ RESUME ================" -ForegroundColor Yellow
    if ($allResults.Count -eq 0) {
        Write-Host "Aucune mise a jour n'etait disponible. Le systeme est deja a jour." -ForegroundColor Green
    } else {
        Write-Host ("{0} element(s) traite(s) : {1} mise(s) a jour, {2} pilote(s)." -f `
            $allResults.Count, $resultWindows.Count, $resultDrivers.Count) -ForegroundColor Green
        Write-Host ""
        $allResults |
            Select-Object @{N='Resultat'; E={ $_.Result }},
                          @{N='KB';       E={ $_.KB }},
                          @{N='Taille';   E={ $_.Size }},
                          @{N='Titre';    E={ $_.Title }} |
            Format-Table -AutoSize -Wrap | Out-Host
    }
    if ($rebootNeeded) {
        Write-Host "Un redemarrage est necessaire pour finaliser les mises a jour." -ForegroundColor Yellow
    }
    Write-Host "=======================================" -ForegroundColor Yellow
    Write-Host ""

    if ($rebootNeeded) {
        Send-Notice "Mises a jour installees" "Redemarrez le PC pour les appliquer (Demarrer > Alimentation > Redemarrer). Arreter puis rallumer ne suffit pas."
    } elseif ($allResults.Count -gt 0) {
        Send-Notice "Mises a jour terminees" "$($allResults.Count) element(s) installe(s). Aucun redemarrage necessaire."
    }
}
catch {
    $exitCode = 1
    Write-Host "ECHEC : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Send-Notice "Echec des mises a jour" "Le detail est dans le journal : $LogFile"
}
finally {
    Stop-Transcript | Out-Null
}

Exit $exitCode
