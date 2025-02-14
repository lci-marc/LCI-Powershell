<#
.SYNOPSIS
Script de migration d'AD Connect vers Entra ID Cloud Sync.

.DESCRIPTION
Ce script gère la migration complète d'un environnement Active Directory synchronisé via AD Connect 
vers une solution de synchronisation Entra ID Cloud Sync. Il inclut les étapes suivantes :
- Validation des prérequis et de l'environnement
- Sauvegarde des configurations existantes
- Installation et configuration de Cloud Sync
- Migration progressive des utilisateurs
- Validation et monitoring
- Procédures de rollback

.PARAMETER TestMode
Switch qui permet d'exécuter le script en mode test sans appliquer les modifications.
Par défaut : False

.EXAMPLE
.\Migrate-ADConnectToCloudSync.ps1
Exécute le script en mode normal avec confirmation utilisateur.

.EXAMPLE
.\Migrate-ADConnectToCloudSync.ps1 -TestMode
Exécute le script en mode test sans appliquer les modifications.

.NOTES
Version         : 1.0
Auteur          : [Marc Bourget]
Date création   : 13/02/2025
Dernière MAJ    : 13/02/2025

Prérequis :
- PowerShell 5.1 ou supérieur
- Modules requis : ActiveDirectory, AzureAD, MSOnline, Az.Monitor
- Droits administrateur local
- Droits Global Administrator sur Azure AD
- Ports 443 sortant ouvert vers Azure
- Niveau fonctionnel AD minimum : Windows Server 2003

Environnement supporté :
- Windows Server 2016 ou supérieur
- Active Directory Domain Services
- Azure AD Premium P1 minimum

Structure des dossiers créés :
C:\Logs\CloudSync-Migration         : Logs d'exécution
C:\CloudSync-Migration\Config       : Fichiers de configuration
C:\CloudSync-Migration\Backup       : Sauvegardes AD Connect

Références :
- https://learn.microsoft.com/fr-fr/entra/identity/cloud-sync/what-is-cloud-sync
- https://learn.microsoft.com/fr-fr/entra/identity/cloud-sync/how-to-install
- https://learn.microsoft.com/fr-fr/entra/identity/cloud-sync/how-to-configure
- https://learn.microsoft.com/fr-fr/entra/identity/cloud-sync/how-to-configure-filtering
- https://learn.microsoft.com/fr-fr/entra/identity/cloud-sync/how-to-monitor
- https://learn.microsoft.com/fr-fr/entra/identity/cloud-sync/how-to-troubleshoot

Fonctionnalités principales :
1. Validation de l'environnement
   - Vérification des prérequis
   - Test des connexions
   - Validation des permissions
   - Inventaire AD

2. Sauvegarde et sécurité
   - Backup configuration AD Connect
   - Export des règles de synchronisation
   - Documentation des paramètres

3. Déploiement Cloud Sync
   - Installation des agents
   - Configuration du compte de service
   - Paramétrage des règles de sync
   - Tests de validation

4. Migration
   - Migration progressive par OU
   - Validation des synchronisations
   - Monitoring des erreurs
   - Procédures de rollback

5. Post-migration
   - Désactivation AD Connect
   - Configuration monitoring
   - Nettoyage
   - Documentation

Logs et monitoring :
- Tous les logs sont stockés dans C:\Logs\CloudSync-Migration
- Format : Date|Niveau|Message
- Niveaux : Information, Warning, Error
- Rétention configurable (défaut : 30 jours)

Sécurité :
- Validation des permissions avant exécution
- Mode test disponible
- Sauvegarde automatique des configurations
- Procédures de rollback documentées

Support et maintenance :
- Le script inclut des fonctions de diagnostic
- Procédures de rollback par étape
- Documentation des erreurs courantes
- Export des logs pour analyse

.LINK
https://learn.microsoft.com/fr-fr/entra/identity/cloud-sync/what-is-cloud-sync

.LINK
https://learn.microsoft.com/fr-fr/entra/identity/hybrid/connect/whatis-azure-ad-connect
#>

#Requires -Version 5.1
#Requires -Modules ActiveDirectory, AzureAD, MSOnline, Az.Monitor
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$TestMode
) 

# Configuration des paramètres d'erreur
$ErrorActionPreference = "Stop"

# Variables globales
$Global:LogPath = "C:\Logs\CloudSync-Migration"
$Global:ConfigPath = "C:\CloudSync-Migration\Config"
$Global:BackupPath = "C:\CloudSync-Migration\Backup"
$Global:Date = Get-Date -Format "yyyyMMdd-HHmmss"
$Global:TestMode = $false

# Fonction de validation des connexions
function Test-RequiredConnections {
    Write-MigrationLog "Vérification des connexions requises..."
    
    try {
        # Vérification de la connexion Azure AD
        try {
            Get-AzureADTenantDetail -ErrorAction Stop
        }
        catch {
            Write-MigrationLog "Connexion à Azure AD requise" -Level Warning
            Connect-AzureAD
        }
        
        # Vérification de la connexion Azure
        try {
            Get-AzContext -ErrorAction Stop
        }
        catch {
            Write-MigrationLog "Connexion Azure requise" -Level Warning
            Connect-AzAccount
        }
        
        Write-MigrationLog "Connexions vérifiées avec succès"
        return $true
    }
    catch {
        Write-MigrationLog "Erreur lors de la vérification des connexions : $_" -Level Error
        return $false
    }
}

# Fonction de validation des permissions
function Test-RequiredPermissions {
    Write-MigrationLog "Vérification des permissions..."
    
    try {
        # Vérification des permissions AD
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
        $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
        
        if (-not $principal.IsInRole($adminRole)) {
            throw "Permissions administrateur requises"
        }
        
        # Vérification des permissions Azure AD
        $roles = Get-AzureADDirectoryRole | Where-Object {$_.DisplayName -eq "Global Administrator"}
        $members = Get-AzureADDirectoryRoleMember -ObjectId $roles[0].ObjectId
        $userUpn = (Get-AzureADCurrentSessionInfo).Account.Id
        
        if (-not ($members | Where-Object {$_.UserPrincipalName -eq $userUpn})) {
            throw "Rôle Global Administrator Azure AD requis"
        }
        
        Write-MigrationLog "Permissions vérifiées avec succès"
        return $true
    }
    catch {
        Write-MigrationLog "Erreur lors de la vérification des permissions : $_" -Level Error
        return $false
    }
}

[Le reste du script précédent reste identique jusqu'à la fonction Test-CloudSyncValidation]

# Fonction de rollback
function Start-MigrationRollback {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Stage
    )
    
    Write-MigrationLog "Démarrage du rollback depuis l'étape : $Stage" -Level Warning
    
    try {
        switch ($Stage) {
            "CloudSync" {
                # Désactivation de Cloud Sync
                Write-MigrationLog "Désactivation de Cloud Sync..."
                Get-Service -Name "AADConnectProvisioningAgent" | Stop-Service -Force
                Set-Service -Name "AADConnectProvisioningAgent" -StartupType Disabled
            }
            "ADConnect" {
                # Réactivation d'AD Connect
                Write-MigrationLog "Réactivation d'AD Connect..."
                Set-Service -Name "ADSync" -StartupType Automatic
                Start-Service -Name "ADSync"
                Set-ADSyncScheduler -SyncCycleEnabled $true
            }
            "ServiceAccount" {
                # Suppression du compte de service Cloud Sync
                Write-MigrationLog "Suppression du compte de service..."
                Get-ADUser "svc-CloudSync" | Remove-ADUser -Confirm:$false
            }
        }
        
        Write-MigrationLog "Rollback terminé avec succès"
        return $true
    }
    catch {
        Write-MigrationLog "Erreur lors du rollback : $_" -Level Error
        return $false
    }
}

# Fonction de test de connectivité
function Test-CloudSyncConnectivity {
    Write-MigrationLog "Test de connectivité Cloud Sync..."
    
    try {
        $endpoints = @(
            "https://graph.windows.net",
            "https://graph.microsoft.com",
            "https://login.microsoftonline.com",
            "https://devicemanagement.microsoft.com"
        )
        
        $results = foreach ($endpoint in $endpoints) {
            $test = Test-NetConnection -ComputerName ($endpoint -replace "https://", "") -Port 443
            [PSCustomObject]@{
                Endpoint = $endpoint
                Connected = $test.TcpTestSucceeded
                LatencyMS = $test.PingReplyDetails.RoundtripTime
            }
        }
        
        $results | Export-Csv -Path (Join-Path $Global:LogPath "Connectivity_$($Global:Date).csv") -NoTypeInformation
        
        if ($results | Where-Object {-not $_.Connected}) {
            throw "Certains endpoints ne sont pas accessibles"
        }
        
        Write-MigrationLog "Test de connectivité réussi"
        return $true
    }
    catch {
        Write-MigrationLog "Erreur lors du test de connectivité : $_" -Level Error
        return $false
    }
}

# Fonction de nettoyage
function Start-MigrationCleanup {
    param(
        [int]$RetentionDays = 30
    )
    
    Write-MigrationLog "Début du nettoyage..."
    
    try {
        # Nettoyage des anciens logs
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
        Get-ChildItem -Path $Global:LogPath -File | 
            Where-Object {$_.LastWriteTime -lt $cutoffDate} | 
            Remove-Item -Force
        
        # Compression des sauvegardes
        $backupZip = Join-Path $Global:BackupPath "Backup_$($Global:Date).zip"
        Compress-Archive -Path "$Global:BackupPath\*" -DestinationPath $backupZip -Force
        
        # Nettoyage des fichiers temporaires
        Get-ChildItem -Path $Global:ConfigPath -File -Filter "*.tmp" | Remove-Item -Force
        
        Write-MigrationLog "Nettoyage terminé avec succès"
        return $true
    }
    catch {
        Write-MigrationLog "Erreur lors du nettoyage : $_" -Level Error
        return $false
    }
}

# Menu principal mis à jour
function Show-MigrationMenu {
    do {
        Clear-Host
        Write-Host "=== Menu de Migration AD Connect vers Cloud Sync ===" -ForegroundColor Cyan
        Write-Host "1. Initialiser l'environnement"
        Write-Host "2. Vérifier les connexions et permissions"
        Write-Host "3. Vérifier les prérequis"
        Write-Host "4. Sauvegarder la configuration AD Connect"
        Write-Host "5. Créer l'inventaire AD"
        Write-Host "6. Tester la connectivité"
        Write-Host "7. Installer l'agent Cloud Sync"
        Write-Host "8. Configurer le compte de service"
        Write-Host "9. Valider la synchronisation"
        Write-Host "10. Désactiver AD Connect"
        Write-Host "11. Configurer le monitoring"
        Write-Host "12. Exécuter le nettoyage"
        Write-Host "13. Exécuter toutes les étapes"
        Write-Host "R. Démarrer un rollback"
        Write-Host "Q. Quitter"
        
        $choice = Read-Host "Choisissez une option"
        
        switch ($choice) {
            "1" { Initialize-MigrationEnvironment }
            "2" { 
                Test-RequiredConnections
                Test-RequiredPermissions 
            }
            "3" { Test-MigrationPrerequisites }
            "4" { Backup-ADConnectConfiguration }
            "5" { Get-ADInventory }
            "6" { Test-CloudSyncConnectivity }
            "7" { 
                $installerPath = Read-Host "Chemin de l'installeur (vide pour télécharger)"
                Install-CloudSyncAgent -InstallerPath $installerPath 
            }
            "8" { 
                $password = Read-Host "Mot de passe du compte de service" -AsSecureString
                New-CloudSyncServiceAccount -ServiceAccountPassword $password 
            }
            "9" { 
                $testOU = Read-Host "OU de test"
                Test-CloudSyncValidation -TestOU $testOU 
            }
            "10" { Disable-ADConnect }
            "11" { Set-CloudSyncMonitoring }
            "12" { 
                $days = Read-Host "Nombre de jours de rétention"
                Start-MigrationCleanup -RetentionDays ([int]$days) 
            }
            "13" {
                Initialize-MigrationEnvironment
                if (Test-RequiredConnections -and Test-RequiredPermissions) {
                    if (Test-MigrationPrerequisites) {
                        Backup-ADConnectConfiguration
                        Get-ADInventory
                        if (Test-CloudSyncConnectivity) {
                            Install-CloudSyncAgent
                            $password = Read-Host "Mot de passe du compte de service" -AsSecureString
                            New-CloudSyncServiceAccount -ServiceAccountPassword $password
                            $testOU = Read-Host "OU de test"
                            if (Test-CloudSyncValidation -TestOU $testOU) {
                                Disable-ADConnect
                                Set-CloudSyncMonitoring
                                Start-MigrationCleanup
                            }
                        }
                    }
                }
            }
            "R" {
                $stage = Read-Host "Étape de rollback (CloudSync/ADConnect/ServiceAccount)"
                Start-MigrationRollback -Stage $stage
            }
            "Q" { return }
        }
        
        if ($choice -ne "Q") {
            Write-Host "`nAppuyez sur une touche pour continuer..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    } while ($choice -ne "Q")
}

# Point d'entrée du script
try {
    # Vérification du mode d'exécution
    if ($MyInvocation.Line -notmatch "-TestMode") {
        Write-Warning "Ce script va effectuer des modifications importantes dans votre environnement."
        Write-Warning "Utilisez le paramètre -TestMode pour exécuter en mode test."
        $confirmation = Read-Host "Êtes-vous sûr de vouloir continuer ? (O/N)"
        if ($confirmation -ne "O") {
            throw "Opération annulée par l'utilisateur"
        }
    }
    else {
        $Global:TestMode = $true
        Write-Host "Exécution en mode test" -ForegroundColor Yellow
    }
    
    # Démarrage du menu
    Show-MigrationMenu
}
catch {
    Write-Error $_.Exception.Message
}
finally {
    # Nettoyage final
    Write-Host "`nFin du script de migration" -ForegroundColor Cyan
}