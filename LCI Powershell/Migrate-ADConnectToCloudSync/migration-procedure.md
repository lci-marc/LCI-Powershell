# Procédure de Migration AD Connect vers Entra Cloud Sync

## Table des matières
1. [Prérequis et Validation](#1-prérequis-et-validation)
2. [Phase de Préparation](#2-phase-de-préparation)
3. [Installation et Configuration](#3-installation-et-configuration)
4. [Phase de Test](#4-phase-de-test)
5. [Migration Progressive](#5-migration-progressive)
6. [Basculement Final](#6-basculement-final)
7. [Post-Migration](#7-post-migration)
8. [Annexes](#8-annexes)

## 1. Prérequis et Validation

### 1.1 Vérification de l'environnement
- Niveau fonctionnel de forêt AD minimum : Windows Server 2003
- Niveau fonctionnel recommandé : Windows Server 2012 R2 ou supérieur
- Version de Windows Server pour les agents : 2016 ou supérieur
- Bande passante minimale : 1 Mbps par agent
- Ports requis : 443 (HTTPS) sortant

### 1.2 Commandes de validation préalable
```powershell
# Vérification des niveaux fonctionnels
Get-ADForest | Select-Object ForestMode
Get-ADDomain | Select-Object DomainMode

# Vérification de la configuration AD Connect existante
Get-ADSyncScheduler
Get-ADSyncConnector | Select-Object Name, Type
```

### 1.3 Licences requises
- Vérifier les licences Entra ID Premium P1/P2 selon les besoins
- Valider les licences pour les fonctionnalités avancées (MFA, PIM, etc.)

## 2. Phase de Préparation

### 2.1 Inventaire des ressources
```powershell
# Export des utilisateurs AD
Get-ADUser -Filter * -Properties * | Export-Csv -Path "AD_Users_Inventory.csv"

# Export des groupes et appartenances
Get-ADGroup -Filter * -Properties * | Export-Csv -Path "AD_Groups_Inventory.csv"

# Export des configurations AD Connect
Get-ADSyncServerConfiguration -Path "ADConnect_Config_Backup"
```

### 2.2 Documentation de l'existant
- Capture des règles de synchronisation actuelles
- Liste des filtres de synchronisation par OU
- Inventaire des applications connectées à Entra ID
- Documentation des workflows automatisés

### 2.3 Nettoyage des données
```powershell
# Identification des doublons d'UPN
$duplicateUPNs = Get-ADUser -Filter * -Properties UserPrincipalName |
    Group-Object UserPrincipalName |
    Where-Object {$_.Count -gt 1}

# Vérification des attributs requis
$usersWithoutMail = Get-ADUser -Filter * -Properties mail |
    Where-Object {-not $_.mail}
```

## 3. Installation et Configuration

### 3.1 Installation des agents Cloud Sync
```powershell
# Téléchargement de l'agent
Invoke-WebRequest -Uri "https://download.msappproxy.net/Subscription/d3c8b69d-6bf7-42be-a529-3fe9c2e70c90/Connector/ProvisioningAgent.msi" -OutFile "ProvisioningAgent.msi"

# Installation silencieuse
msiexec /i ProvisioningAgent.msi /qn
```

### 3.2 Configuration des connecteurs
1. Dans le portail Entra ID :
   - Accéder à Cloud Sync
   - Créer une nouvelle configuration
   - Sélectionner "Active Directory" comme source

2. Configuration du compte de service :
```powershell
# Création du compte de service
New-ADUser -Name "svc-CloudSync" -UserPrincipalName "svc-CloudSync@domain.com"

# Attribution des permissions
$user = Get-ADUser "svc-CloudSync"
$ou = Get-ADOrganizationalUnit -Filter 'Name -like "*"'
$acl = Get-Acl "AD:$($ou.DistinguishedName)"
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($user.SID,"ReadProperty","Allow")
$acl.AddAccessRule($ace)
Set-Acl -AclObject $acl "AD:$($ou.DistinguishedName)"
```

## 4. Phase de Test

### 4.1 Configuration de l'environnement de test
1. Création d'une OU de test
```powershell
New-ADOrganizationalUnit -Name "CloudSync-Test" -Path "DC=domain,DC=com"
```

2. Configuration des filtres de synchronisation
- Limiter la synchronisation à l'OU de test
- Configurer les attributs à synchroniser

### 4.2 Tests de validation
```powershell
# Script de validation de synchronisation
$testUsers = Get-AzureADUser -Filter "Department eq 'Test'"
foreach ($user in $testUsers) {
    $adUser = Get-ADUser -Filter {UserPrincipalName -eq $user.UserPrincipalName} -Properties *
    
    # Validation des attributs critiques
    $comparison = @{
        "UPN" = $user.UserPrincipalName -eq $adUser.UserPrincipalName
        "Email" = $user.Mail -eq $adUser.Mail
        "DisplayName" = $user.DisplayName -eq $adUser.DisplayName
    }
    
    $comparison | Format-Table
}
```

## 5. Migration Progressive

### 5.1 Planification des vagues de migration
1. Identification des groupes d'utilisateurs
2. Création du calendrier de migration
3. Définition des critères de succès

### 5.2 Processus de migration par vague
```powershell
# Exemple de script de migration pour une OU
$ouDN = "OU=Marketing,DC=domain,DC=com"
$users = Get-ADUser -Filter * -SearchBase $ouDN

# Validation pré-migration
$validation = foreach ($user in $users) {
    @{
        "SamAccountName" = $user.SamAccountName
        "UPN" = $user.UserPrincipalName
        "Enabled" = $user.Enabled
        "RequiredAttributes" = Test-ADUser $user.SamAccountName
    }
}

$validation | Export-Csv "PreMigration_Validation.csv"
```

## 6. Basculement Final

### 6.1 Vérification pré-basculement
```powershell
# Vérification de la synchronisation
$syncStatus = Get-AzureADDirectoryServicePrincipal | 
    Where-Object {$_.DisplayName -eq "Windows Azure Active Directory Sync"}

# Analyse des erreurs de synchronisation
Get-EventLog -LogName Application -Source "Microsoft Azure AD Sync" -Newest 50 |
    Where-Object {$_.EntryType -eq "Error"}
```

### 6.2 Désactivation d'AD Connect
```powershell
# Désactivation de la synchronisation
Set-ADSyncScheduler -SyncCycleEnabled $false

# Sauvegarde de la configuration
$date = Get-Date -Format "yyyyMMdd"
Export-AADConnectConfiguration -Path "C:\Backup\ADConnect_$date.json"
```

### 6.3 Activation complète de Cloud Sync
1. Suppression des filtres de synchronisation
2. Activation de la synchronisation complète
3. Validation de la synchronisation globale

## 7. Post-Migration

### 7.1 Surveillance et monitoring
```powershell
# Configuration des alertes Azure Monitor
$actionGroup = New-AzActionGroup -ResourceGroupName "Monitoring" `
    -Name "CloudSync-Alerts" `
    -ShortName "CloudSync" `
    -Receiver @{
        Name = "EmailAlert"
        ReceiverType = "Email"
        EmailAddress = "admin@domain.com"
    }

# Création des règles d'alerte
New-AzMetricAlertRule -Name "CloudSync-FailedSync" `
    -ResourceGroupName "Monitoring" `
    -TargetResourceId "/subscriptions/.../providers/Microsoft.CloudSync" `
    -MetricName "FailedSyncCount" `
    -Operator GreaterThan `
    -Threshold 0 `
    -WindowSize "00:05:00" `
    -TimeAggregationOperator Total `
    -Actions $actionGroup
```

### 7.2 Documentation finale
- Mise à jour des procédures opérationnelles
- Documentation des configurations finales
- Création des procédures de support

## 8. Annexes

### 8.1 Scripts utiles
```powershell
# Fonction de test des attributs requis
function Test-ADUser {
    param($SamAccountName)
    
    $user = Get-ADUser $SamAccountName -Properties *
    $required = @("mail", "displayName", "givenName", "sn")
    
    $results = foreach ($attr in $required) {
        @{
            Attribute = $attr
            Present = ![string]::IsNullOrEmpty($user.$attr)
            Value = $user.$attr
        }
    }
    
    return $results
}

# Fonction de validation de synchronisation
function Test-CloudSyncUser {
    param($UserPrincipalName)
    
    $adUser = Get-ADUser -Filter {UserPrincipalName -eq $UserPrincipalName} -Properties *
    $azureUser = Get-AzureADUser -ObjectId $UserPrincipalName
    
    $comparison = @{
        UPN = $adUser.UserPrincipalName -eq $azureUser.UserPrincipalName
        DisplayName = $adUser.DisplayName -eq $azureUser.DisplayName
        Mail = $adUser.mail -eq $azureUser.Mail
    }
    
    return $comparison
}
```

### 8.2 Références
- [Documentation Cloud Sync](https://learn.microsoft.com/fr-fr/entra/identity/cloud-sync/what-is-cloud-sync)
- [Guide de déploiement](https://learn.microsoft.com/fr-fr/entra/identity/cloud-sync/how-to-install)
- [Résolution des problèmes](https://learn.microsoft.com/fr-fr/entra/identity/cloud-sync/how-to-troubleshoot)
- [Bonnes pratiques de migration](https://learn.microsoft.com/fr-fr/entra/architecture/identity-migrate-ad-to-azure)
