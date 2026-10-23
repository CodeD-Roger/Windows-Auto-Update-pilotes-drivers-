# ============================================================
#  auto_update.ps1
#  Mise a jour automatique : Windows + Pilotes + Applications
#  - Silencieux (tourne en arriere-plan, priorite basse)
#  - Pas de redemarrage automatique
#  - Les mises a jour systeme s'appliquent au prochain REDEMARRAGE
#    (avec le demarrage rapide, "Arreter" ne suffit pas)
#  - Journal de chaque execution dans
#    C:\ProgramData\AutoWindowsUpdate\logs\
#
#  Etapes (chacune independante : un echec n'arrete pas les autres) :
#    1. Signatures Microsoft Defender
#    2. Windows Update : systeme, securite, produits Microsoft
#    3. Pilotes via Windows Update
#    4. Microsoft 365 / Office (Click-to-Run)
#    5. Applications du Microsoft Store
#    6. Applications classiques via winget (installe si absent)
#
#  Parametres :
#    -RegisterStartup    Installe le script dans Program Files et
#                        cree une tache planifiee (au demarrage et a
#                        l'ouverture de session), puis quitte.
#    -UnregisterStartup  Supprime cette tache et la copie installee,
#                        puis quitte.
#    -Scheduled          Utilise par la tache : ne fait rien si la
#                        derniere execution date de moins de 20 h.
#
#  Exemples :
#    .\auto_update.ps1                     # execution immediate
#    .\auto_update.ps1 -RegisterStartup    # activer l'automatisme
#    .\auto_update.ps1 -UnregisterStartup  # desactiver l'automatisme
# ============================================================

param(
    [switch]$RegisterStartup,
    [switch]$UnregisterStartup,
    [switch]$Scheduled
)

# ── Verification des droits admin ──────────────────────────
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Warning "Ce script doit etre lance en tant qu'Administrateur."
    Exit 1
}

# ── Emplacements et reglages ───────────────────────────────
$TaskName   = "AutoWindowsUpdate-AtStartup"
# Program Files : seuls les administrateurs peuvent y ecrire. La tache
# tourne en SYSTEM ; si elle lancait une copie modifiable par un simple
# utilisateur (Telechargements, Bureau...), cet utilisateur pourrait y
# glisser ses propres commandes et les faire executer en SYSTEM.
$InstallDir = Join-Path $env:ProgramFiles "AutoWindowsUpdate"
$Installed  = Join-Path $InstallDir "auto_update.ps1"
$DataDir    = Join-Path $env:ProgramData "AutoWindowsUpdate"
$LogDir     = Join-Path $DataDir "logs"
$LastRun    = Join-Path $DataDir "last_run.txt"
$KeepLogs   = 30
$MinHoursBetweenRuns = 20

# Applications que winget ne doit PAS mettre a jour
# (elles se mettent a jour seules, ou une mise a jour silencieuse
#  risquerait de casser quelque chose). Ids visibles avec : winget list
$WingetExclusions = @(
    "VMware.WorkstationPro",          # telechargement Broadcom avec compte, VMs en cours
    "Valve.Steam",                    # se met a jour tout seul
    "EpicGames.EpicGamesLauncher",    # se met a jour tout seul
    "Nvidia.GeForceExperience",       # pilotes geres par l'app NVIDIA
    "Nvidia.PhysX"
)

# Pilotes Windows Update a ne PAS installer (expression reguliere sur le
# titre, insensible a la casse). Ils sont MASQUES dans Windows Update :
# ni le script ni Windows ne les installeront.
# Ici : composants ASUS qui reinstallent Armoury Crate / MyASUS
# (System Control Interface, Armoury Crate Control Interface, pilotes
# souris/clavier ROG avec ArmouryCrateDownloadTool, extensions).
# Titres vus : "ASUSTeK Computer Inc. Mouse Driver Update (1.0.72.0)",
#              "ASUSTeK Computer Inc. - Keyboard - 1.0.25.0".
# Le pave tactile et le firmware restent mis a jour.
# Laisser vide ("") pour tout installer.
$DriverExclusions = '^ASUSTeK .*\b(System|Mouse|Keyboard|Extension|SoftwareComponent)\b'

# ── Activer le lancement automatique ───────────────────────
if ($RegisterStartup) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $source = $MyInvocation.MyCommand.Path
    if ($source -ne $Installed) {
        Copy-Item -LiteralPath $source -Destination $Installed -Force
    }

    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
        -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Installed`" -Scheduled"

    # Deux declencheurs, 2 min apres pour ne pas ralentir le PC :
    #  - au demarrage ;
    #  - a l'ouverture de session. Avec le demarrage rapide (actif par
    #    defaut), "Arreter" puis rallumer n'est pas un demarrage : sans
    #    ce second declencheur, la tache ne tournerait presque jamais.
    # -Scheduled limite a une execution toutes les 20 h.
    $atStartup = New-ScheduledTaskTrigger -AtStartup
    $atStartup.Delay = "PT2M"
    $atLogOn = New-ScheduledTaskTrigger -AtLogOn
    $atLogOn.Delay = "PT2M"

    # Priorite 7 = en dessous de la normale : le PC reste fluide.
    # Une seule execution a la fois, trois heures maximum.
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 3) `
        -Priority 7

    # Compte SYSTEM = droits admin, sans ouverture de session requise.
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
        -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName `
        -Action $action -Trigger @($atStartup, $atLogOn) -Settings $settings `
        -Principal $principal -Force | Out-Null

    Write-Host "Script installe dans : $Installed"
    Write-Host "Tache '$TaskName' creee : au demarrage et a l'ouverture de session (1 fois / $MinHoursBetweenRuns h max)."
    Write-Host "Journaux : $LogDir"
    Write-Host "Pensez a relancer -RegisterStartup apres chaque modification du script."
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

# ── Une execution toutes les 20 h maximum (tache planifiee) ─
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
if ($Scheduled -and (Test-Path -LiteralPath $LastRun)) {
    $last = (Get-Item -LiteralPath $LastRun).LastWriteTime
    if ($last -gt (Get-Date).AddHours(-$MinHoursBetweenRuns)) { Exit 0 }
}

# ── Journal ────────────────────────────────────────────────
# En tache planifiee, la fenetre est cachee : sans journal, rien ne
# dit ce qui a ete installe, ni si l'execution a echoue.
Get-ChildItem -LiteralPath $LogDir -Filter "auto_update_*.log" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip ($KeepLogs - 1) |
    Remove-Item -Force -ErrorAction SilentlyContinue
$LogFile = Join-Path $LogDir ("auto_update_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))
Start-Transcript -LiteralPath $LogFile | Out-Null

# Les programmes lances (installeurs) heritent de cette priorite basse
(Get-Process -Id $PID).PriorityClass = "BelowNormal"

# PowerShell 5.1 ne propose pas toujours TLS 1.2 par defaut :
# sans lui, PSGallery et GitHub refusent la connexion.
[Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$failures = @()

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "── $Text" -ForegroundColor Cyan
}

function Add-Failure([string]$Step, $ErrorRecord) {
    $script:failures += $Step
    Write-Host "ECHEC ($Step) : $($ErrorRecord.Exception.Message)" -ForegroundColor Red
}

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

# ── Attente du reseau (jusqu'a 5 min apres le demarrage) ───
Write-Step "Attente de la connexion reseau..."
$online   = $false
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
    if (Resolve-DnsName "www.msftconnecttest.com" -QuickTimeout -ErrorAction SilentlyContinue) {
        $online = $true
        break
    }
    Start-Sleep -Seconds 15
}
if (-not $online) {
    # Pas d'horodatage : la prochaine ouverture de session reessaiera
    Write-Warning "Pas de reseau apres 5 minutes, abandon."
    Stop-Transcript | Out-Null
    Exit 1
}

# ── 1. Signatures Microsoft Defender ───────────────────────
Write-Step "Mise a jour des signatures Defender..."
try {
    Update-MpSignature -ErrorAction Stop
    Write-Host "Signatures a jour."
} catch { Add-Failure "Defender" $_ }

# ── 2 et 3. Windows Update + pilotes ───────────────────────
# -IgnoreReboot : ne jamais redemarrer, et ne jamais POSER la
#                 question. Sans lui, le module demande s'il faut
#                 redemarrer : dans une tache cachee, personne ne
#                 repond et le script reste bloque.
# -AcceptAll    : accepte toutes les mises a jour sans confirmation
# -Install      : telecharge et installe directement
$resultWindows = @()
$resultDrivers = @()
try {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        Install-Module -Name PSWindowsUpdate -Repository PSGallery -Force -Scope AllUsers -Confirm:$false
    }
    Import-Module PSWindowsUpdate -Force -ErrorAction Stop

    Write-Step "Recherche et installation des mises a jour Windows..."
    $resultWindows = @(Get-WindowsUpdate `
        -MicrosoftUpdate `
        -UpdateType Software `
        -NotCategory "Language packs" `
        -AcceptAll -Install -IgnoreReboot -ErrorAction Stop | ForEach-Object { $_ } | Where-Object { $_ })

    # Pilotes publies par les fabricants via Windows Update
    Write-Step "Recherche et installation des pilotes..."
    # Get-WindowsUpdate renvoie la liste en un seul objet :
    # ForEach-Object { $_ } la deroule element par element.
    if ($DriverExclusions) {
        $excluded = @(Get-WindowsUpdate -MicrosoftUpdate -UpdateType Driver -ErrorAction Stop |
            ForEach-Object { $_ } |
            Where-Object { $_.Title -match $DriverExclusions })
        if ($excluded) {
            $excluded | ForEach-Object { Write-Host "Pilote masque : $($_.Title)" }
            Get-WindowsUpdate -MicrosoftUpdate -UpdateID @($excluded | ForEach-Object { $_.Identity.UpdateID }) `
                -Hide -AcceptAll -ErrorAction Stop | Out-Null
        }
    }
    $resultDrivers = @(Get-WindowsUpdate `
        -MicrosoftUpdate `
        -UpdateType Driver `
        -AcceptAll -Install -IgnoreReboot -ErrorAction Stop | ForEach-Object { $_ } | Where-Object { $_ })

    $allResults = $resultWindows + $resultDrivers
    if ($allResults.Count -eq 0) {
        Write-Host "Aucune mise a jour Windows ni pilote disponible."
    } else {
        $allResults |
            Select-Object @{N='Resultat'; E={ $_.Result }},
                          @{N='KB';       E={ $_.KB }},
                          @{N='Taille';   E={ $_.Size }},
                          @{N='Titre';    E={ $_.Title }} |
            Format-Table -AutoSize -Wrap | Out-Host
    }
} catch { Add-Failure "Windows Update" $_ }

# ── 4. Microsoft 365 / Office (Click-to-Run) ───────────────
# forceappshutdown=false : si Word/Outlook sont ouverts, la mise a
# jour attend leur fermeture au lieu de les fermer.
$c2r = Join-Path $env:CommonProgramFiles "microsoft shared\ClickToRun\OfficeC2RClient.exe"
if (Test-Path -LiteralPath $c2r) {
    Write-Step "Mise a jour de Microsoft 365..."
    try {
        Start-Process -FilePath $c2r -ErrorAction Stop `
            -ArgumentList "/update user updatepromptuser=false forceappshutdown=false displaylevel=false"
        Write-Host "Mise a jour Office lancee."
    } catch { Add-Failure "Office" $_ }
}

# ── 5. Applications du Microsoft Store ─────────────────────
# Ne fonctionne qu'en SYSTEM (cas de la tache planifiee).
if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    Write-Step "Mise a jour des applications du Microsoft Store..."
    try {
        Get-CimInstance -Namespace "root\cimv2\mdm\dmmap" `
            -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" -ErrorAction Stop |
            Invoke-CimMethod -MethodName UpdateScanMethod -ErrorAction Stop | Out-Null
        Write-Host "Recherche de mises a jour Store declenchee."
    } catch { Add-Failure "Microsoft Store" $_ }
}

# ── 6. Applications via winget ────────────────────────────
function Get-WingetPath {
    # En session utilisateur : alias d'execution dans le PATH
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # En SYSTEM : pas d'alias, on va chercher l'exe dans le paquet
    $exe = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object { [version](($_.Directory.Name -split '_')[1]) } |
        Select-Object -Last 1
    if ($exe) { return $exe.FullName }
    return $null
}

# Installe winget (App Installer) depuis la derniere version officielle
# de github.com/microsoft/winget-cli, pour tous les utilisateurs.
# Repair-WinGetPackageManager n'existe pas sous Windows PowerShell 5.1.
function Install-Winget {
    $tmp = Join-Path $env:TEMP ("winget_" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -UseBasicParsing
        $assets  = @{}
        foreach ($pattern in '\.msixbundle$', '^DesktopAppInstaller_Dependencies\.zip$', '_License1\.xml$') {
            $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
            if (-not $asset) { throw "Fichier '$pattern' absent de la version $($release.tag_name)." }
            $path = Join-Path $tmp $asset.name
            Invoke-WebRequest $asset.browser_download_url -OutFile $path -UseBasicParsing
            $assets[$pattern] = $path
        }
        $bundle = $assets['\.msixbundle$']

        # On n'installe que ce qui est signe par Microsoft
        $sig = Get-AuthenticodeSignature -LiteralPath $bundle
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw "Signature du paquet winget invalide ($($sig.Status))."
        }

        $depDir = Join-Path $tmp "deps"
        Expand-Archive -LiteralPath $assets['^DesktopAppInstaller_Dependencies\.zip$'] -DestinationPath $depDir -Force
        $deps = @(Get-ChildItem -Path $depDir -Recurse -Include *.appx, *.msix |
            Where-Object { $_.FullName -match '\\x64\\' } | ForEach-Object { $_.FullName })

        Add-AppxProvisionedPackage -Online -PackagePath $bundle `
            -DependencyPackagePath $deps `
            -LicensePath $assets['_License1\.xml$'] -ErrorAction Stop | Out-Null
        Write-Host "winget $($release.tag_name) installe."
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step "Mise a jour des applications via winget..."
try {
    $winget = Get-WingetPath
    if (-not $winget) {
        Write-Host "winget absent, installation..."
        Install-Winget
        $winget = Get-WingetPath
        if (-not $winget) { throw "winget introuvable apres installation." }
    }
    Write-Host "winget : $winget"
    [Console]::OutputEncoding = [Text.Encoding]::UTF8

    & $winget source update --disable-interactivity | Out-Null

    # Les pins empechent winget de toucher a ces applications
    foreach ($id in $WingetExclusions) {
        & $winget pin add --id $id --exact --accept-source-agreements --disable-interactivity 2>$null | Out-Null
    }

    # Filtre les barres de progression pour garder un journal lisible
    & $winget upgrade --all --silent `
        --accept-package-agreements --accept-source-agreements `
        --disable-interactivity |
        Where-Object { $_ -match '\w' -and $_ -notmatch '[█▒]' } |
        Out-Host
    Write-Host "winget termine (code $LASTEXITCODE)."
} catch { Add-Failure "winget" $_ }

# ── Resume ─────────────────────────────────────────────────
$rebootNeeded = $false
try { $rebootNeeded = [bool](Get-WURebootStatus -Silent) } catch {}

Write-Host ""
Write-Host "================ RESUME ================" -ForegroundColor Yellow
Write-Host ("Windows Update : {0} mise(s) a jour, {1} pilote(s)." -f $resultWindows.Count, $resultDrivers.Count)
if ($failures) {
    Write-Host "Etapes en echec : $($failures -join ', ')" -ForegroundColor Red
}
if ($rebootNeeded) {
    Write-Host "Un redemarrage est necessaire pour finaliser les mises a jour." -ForegroundColor Yellow
}
Write-Host "=======================================" -ForegroundColor Yellow

# Message uniquement s'il y a quelque chose a faire
if ($failures) {
    Send-Notice "Echec des mises a jour" "Etapes en echec : $($failures -join ', '). Detail : $LogFile"
} elseif ($rebootNeeded) {
    Send-Notice "Mises a jour installees" "Redemarrez le PC pour les appliquer (Demarrer > Alimentation > Redemarrer). Arreter puis rallumer ne suffit pas."
}

Set-Content -LiteralPath $LastRun -Value (Get-Date -Format o)
Stop-Transcript | Out-Null

if ($failures) { Exit 1 }
Exit 0
