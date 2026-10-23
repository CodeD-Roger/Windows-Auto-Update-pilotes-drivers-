<div align="center">

# ⚡ auto_update.ps1

**Mise à jour automatique Windows — silencieuse, sans redémarrage forcé**

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows)
![Admin](https://img.shields.io/badge/Requires-Admin-red)

</div>

---

## Description

Script PowerShell qui automatise l'installation des mises à jour Windows, des pilotes et des applications en arrière-plan, sans redémarrage automatique. Les changements système sont appliqués au prochain redémarrage manuel.

---

## Fonctionnalités

- **Windows Update complet** — OS, sécurité, produits Microsoft
- **Pilotes** — publiés par les fabricants via Windows Update
- **Applications** — mise à jour via **winget**, installé automatiquement s'il est absent (paquet officiel `microsoft/winget-cli`, signature Microsoft vérifiée)
- **Microsoft Store** — déclenche la mise à jour des applications du Store
- **Microsoft 365** — mise à jour Click-to-Run, sans fermer Word/Outlook s'ils sont ouverts
- **Defender** — mise à jour des signatures antivirus
- **Exclusions winget** — liste `$WingetExclusions` en haut du script pour les applications à ne pas toucher
- **Silencieux et discret** — aucune fenêtre, priorité CPU basse
- **Sans redémarrage forcé** — les mises à jour attendent le prochain **redémarrage** (avec le démarrage rapide de Windows, « Arrêter » puis rallumer ne suffit pas)
- **Language packs exclus** — évite les téléchargements inutiles
- **Journal** — chaque exécution est consignée dans `C:\ProgramData\AutoWindowsUpdate\logs\` (30 derniers journaux)
- **Message uniquement si nécessaire** — quand il faut redémarrer, ou quand une étape a échoué (code de sortie 1)
- **Étapes indépendantes** — si une étape échoue, les suivantes s'exécutent quand même
- **Lancement automatique** — option intégrée : au démarrage et à l'ouverture de session, une fois toutes les 20 h au plus

> ℹ️ En compte SYSTEM, winget ne voit que les applications installées pour tous les utilisateurs. Les applications installées dans le profil (VS Code « User », GitHub Desktop…) gardent leur propre mise à jour automatique.

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

- se déclenche **au démarrage et à l'ouverture de session** (2 minutes après, pour ne pas ralentir le PC), **une fois toutes les 20 h au plus** ;
- s'exécute avec le compte **SYSTEM** (droits admin, **sans** ouverture de session ni mot de passe) ;
- attend qu'un réseau soit disponible (5 min max), ne tourne qu'une fois à la fois, trois heures au plus ;
- tourne **silencieusement** en arrière-plan, en priorité basse.

> 🔒 **Pourquoi Program Files ?** La tâche tourne en SYSTEM. Si elle lançait la copie de votre dossier Téléchargements, n'importe quel utilisateur du PC pourrait modifier ce fichier et faire exécuter ses propres commandes avec les pleins pouvoirs. Program Files n'est modifiable que par un administrateur. Pour mettre à jour le script, relancez simplement `-RegisterStartup` avec la nouvelle version.

> ⚡ **Pourquoi aussi à l'ouverture de session ?** Avec le démarrage rapide (actif par défaut), « Arrêter » met le PC en veille prolongée : au rallumage, Windows ne considère pas qu'il a démarré, et une tâche « au démarrage » seule pourrait ne presque jamais tourner. Le paramètre `-Scheduled`, passé par la tâche, évite de relancer les mises à jour à chaque session (20 h minimum entre deux exécutions). Lancé à la main, le script tourne toujours.

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

Installés automatiquement s'ils sont absents :

- **PSWindowsUpdate** — depuis PSGallery
- **winget** (App Installer) — dernière version de [microsoft/winget-cli](https://github.com/microsoft/winget-cli/releases), installée pour tous les utilisateurs après vérification de la signature Microsoft. `Repair-WinGetPackageManager` ne fonctionne pas sous Windows PowerShell 5.1, d'où cette méthode.

`-IgnoreReboot` est indispensable : sans lui, le module **demande** s'il faut redémarrer, et dans une tâche cachée personne ne répond.

---

## Fonctionnement

```
1. Vérification des droits admin
2. -Scheduled : sortie immédiate si dernière exécution < 20 h
3. Journal ouvert dans C:\ProgramData\AutoWindowsUpdate\logs\
4. Attente du réseau (5 min max)
5. Update-MpSignature                                       (Defender)
6. Get-WindowsUpdate -MicrosoftUpdate -UpdateType Software -AcceptAll -Install -IgnoreReboot
7. Get-WindowsUpdate -MicrosoftUpdate -UpdateType Driver   -AcceptAll -Install -IgnoreReboot
8. OfficeC2RClient.exe /update                              (Microsoft 365)
9. UpdateScanMethod                                         (Microsoft Store, en SYSTEM)
10. winget upgrade --all --silent                           (applications)
11. Résumé ; message seulement si redémarrage nécessaire ou échec
```

---

## Auteur

**Schems Kerdoncuff** — [CodeD-Roger](https://github.com/CodeD-Roger)
