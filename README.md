<div align="center">

# ⚡ auto_update.ps1

**Mise à jour automatique Windows — silencieuse, sans redémarrage forcé**

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows)
![Admin](https://img.shields.io/badge/Requires-Admin-red)

</div>

---

## Description

Script PowerShell qui automatise l'installation des mises à jour Windows et des pilotes en arrière-plan, sans redémarrage automatique. Les changements sont appliqués au prochain redémarrage manuel.

---

## Fonctionnalités

- **Windows Update complet** — OS, sécurité, mises à jour Microsoft
- **Pilotes** — mise à jour automatique via la catégorie Drivers
- **Silencieux** — tourne en arrière-plan sans fenêtre pop-up
- **Sans redémarrage forcé** — les mises à jour attendent le prochain **redémarrage** (avec le démarrage rapide de Windows, « Arrêter » puis rallumer ne suffit pas)
- **Language packs exclus** — évite les téléchargements inutiles
- **Journal** — chaque exécution est consignée dans `C:\ProgramData\AutoWindowsUpdate\logs\` (30 derniers journaux)
- **Notification** — bulle Windows, ou message aux sessions ouvertes quand le script tourne en tâche planifiée
- **Erreurs signalées** — un échec est notifié, consigné, et le script sort avec le code 1
- **Lancement automatique** — option intégrée : au démarrage et chaque jour à 12:00

---

## Utilisation

> **Requiert des droits Administrateur**

```powershell
# Depuis PowerShell en tant qu'Administrateur
.\auto_update.ps1
```

Ou via le planificateur de tâches Windows pour une exécution automatique :

```powershell
# Créer une tâche planifiée (exemple : tous les dimanches à 3h)
# Le script doit être dans un dossier que seuls les administrateurs
# peuvent modifier (ex. C:\Program Files\AutoWindowsUpdate\).
$action  = New-ScheduledTaskAction -Execute "PowerShell.exe" `
             -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"C:\Program Files\AutoWindowsUpdate\auto_update.ps1`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
$settings = New-ScheduledTaskSettingsSet -RunOnlyIfIdle -IdleDuration 00:10:00
Register-ScheduledTask -TaskName "AutoWindowsUpdate" `
  -Action $action -Trigger $trigger -Settings $settings `
  -RunLevel Highest -Force
```

---

## 🚀 Lancer le script à chaque démarrage

Pour que le script s'exécute **automatiquement à chaque démarrage du PC**, le plus simple est d'utiliser l'option intégrée. Une seule commande à lancer **une fois**, dans un PowerShell **Administrateur** :

```powershell
.\auto_update.ps1 -RegisterStartup
```

Cela copie le script dans `C:\Program Files\AutoWindowsUpdate\` et crée une tâche planifiée nommée `AutoWindowsUpdate-AtStartup` qui :

- se déclenche **à chaque démarrage** (2 minutes après, pour ne pas ralentir l'ouverture de session) **et chaque jour à 12:00** — si le PC était éteint à midi, elle tourne dès qu'il est rallumé ;
- s'exécute avec le compte **SYSTEM** (droits admin, **sans** ouverture de session ni mot de passe) ;
- attend qu'un réseau soit disponible, ne tourne qu'une fois à la fois, deux heures au plus ;
- tourne **silencieusement** en arrière-plan.

> 🔒 **Pourquoi Program Files ?** La tâche tourne en SYSTEM. Si elle lançait la copie de votre dossier Téléchargements, n'importe quel utilisateur du PC pourrait modifier ce fichier et faire exécuter ses propres commandes avec les pleins pouvoirs. Program Files n'est modifiable que par un administrateur. Pour mettre à jour le script, relancez simplement `-RegisterStartup` avec la nouvelle version.

> ⚡ **Pourquoi un déclencheur quotidien ?** Avec le démarrage rapide (actif par défaut), « Arrêter » met le PC en veille prolongée : au rallumage, Windows ne considère pas qu'il a démarré, et une tâche « au démarrage » seule pourrait ne presque jamais tourner sur un portable.

### Désactiver le lancement au démarrage

```powershell
.\auto_update.ps1 -UnregisterStartup
```

Supprime la tâche et la copie de Program Files ; les journaux sont conservés.

### Vérifier / gérer la tâche

```powershell
# Vérifier que la tâche existe
Get-ScheduledTask -TaskName "AutoWindowsUpdate-AtStartup"

# La lancer manuellement pour tester
Start-ScheduledTask -TaskName "AutoWindowsUpdate-AtStartup"
```

Vous pouvez aussi la retrouver dans le **Planificateur de tâches** Windows (`taskschd.msc`), dans la bibliothèque des tâches.

<details>
<summary>Alternative : créer la tâche à la main (sans l'option intégrée)</summary>

```powershell
# À lancer une fois en tant qu'Administrateur
$scriptPath = "C:\Program Files\AutoWindowsUpdate\auto_update.ps1"   # dossier réservé aux administrateurs

$action  = New-ScheduledTaskAction -Execute "PowerShell.exe" `
             -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = "PT2M"
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
               -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
               -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "AutoWindowsUpdate-AtStartup" `
  -Action $action -Trigger $trigger -Settings $settings `
  -Principal $principal -Force
```

</details>

---

## Dépendances

Le module **PSWindowsUpdate** est installé automatiquement s'il est absent :

```powershell
Install-Module -Name PSWindowsUpdate -Repository PSGallery -Force -Scope AllUsers
```

`-IgnoreReboot` est indispensable : sans lui, le module **demande** s'il faut redémarrer, et dans une tâche cachée personne ne répond.

---

## Fonctionnement

```
1. Vérification des droits admin
2. Journal ouvert dans C:\ProgramData\AutoWindowsUpdate\logs\
3. Installation de PSWindowsUpdate si absent (TLS 1.2 forcé)
4. Get-WindowsUpdate -MicrosoftUpdate -UpdateType Software -AcceptAll -Install -IgnoreReboot
5. Get-WindowsUpdate -MicrosoftUpdate -UpdateType Driver   -AcceptAll -Install -IgnoreReboot
6. Résumé, état « redémarrage nécessaire »
7. Notification : « Redémarrez » si besoin, ou l'échec et le chemin du journal
```

---

## Auteur

**Schems Kerdoncuff** — [CodeD-Roger](https://github.com/CodeD-Roger)
