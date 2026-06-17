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
- **Sans redémarrage forcé** — les mises à jour attendent le prochain redémarrage manuel
- **Language packs exclus** — évite les téléchargements inutiles
- **Notification Windows** — alerte visuelle à la fin du processus
- **Lancement au démarrage** — option intégrée pour s'exécuter à chaque démarrage du PC

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
$action  = New-ScheduledTaskAction -Execute "PowerShell.exe" `
             -Argument "-ExecutionPolicy Bypass -File C:\Scripts\auto_update.ps1"
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

Cela crée une tâche planifiée nommée `AutoWindowsUpdate-AtStartup` qui :

- se déclenche **à chaque démarrage** de Windows ;
- s'exécute avec le compte **SYSTEM** (droits admin, **sans** ouverture de session ni mot de passe) ;
- démarre **2 minutes après le boot** pour ne pas ralentir l'ouverture de session ;
- tourne **silencieusement** en arrière-plan.

> ℹ️ Le chemin du script est enregistré tel quel au moment de la commande. Si vous déplacez `auto_update.ps1`, relancez `-RegisterStartup` depuis le nouvel emplacement.

### Désactiver le lancement au démarrage

```powershell
.\auto_update.ps1 -UnregisterStartup
```

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
$scriptPath = "C:\Scripts\auto_update.ps1"   # adaptez le chemin

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
Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers
```

---

## Fonctionnement

```
1. Vérification des droits admin
2. Installation automatique de PSWindowsUpdate si absent
3. Get-WindowsUpdate -AcceptAll -Install -AutoReboot:$false
4. Get-WindowsUpdate -Category "Drivers" -AutoReboot:$false
5. Notification Windows balloon tip (8 secondes)
```

---

## Auteur

**Schems Kerdoncuff** — [CodeD-Roger](https://github.com/CodeD-Roger)
