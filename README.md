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
