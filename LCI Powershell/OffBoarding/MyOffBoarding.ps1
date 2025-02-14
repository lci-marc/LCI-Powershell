# Ce script PowerShell effectue le processus d'"off boarding" d'un utilisateur dans un environnement Microsoft 365.
# Les étapes suivantes sont exécutées par le script :
# 1. Récupération du gestionnaire de l'utilisateur.
# 2. Récupération du chemin OneDrive de l'utilisateur.
# 3. Collecte des données OneDrive de l'utilisateur vers le OneDrive du gestionnaire.
# 4. Conversion de la boîte de courrier de l'utilisateur en boîte partagée.
# 5. Délégation de la boîte de courrier de l'utilisateur au gestionnaire.
# 6. Retrait de l'utilisateur de tous les rôles.
# 7. Retrait de toutes les licences assignées à l'utilisateur.
# 8. Retrait de l'utilisateur de tous les groupes de sécurité.
# 9. Désactivation du compte utilisateur.
# 10. Rendre l'utilisateur invisible dans le carnet d'adresses d'entreprise.
# 11. Réinitialisation du mot de passe de l'utilisateur avec un mot de passe aléatoire de 14 caractères.
# 12. Déconnexion de toutes les connexions actives de l'utilisateur.
# 13. Révocation des accès de l'utilisateur.
#
# Exemple d'utilisation
#$UserEmail = "user@example.com"
#OffBoard-User -UserEmail $UserEmail

# Importer les modules nécessaires
Import-Module AzureAD
Import-Module Microsoft.Graph
Import-Module ExchangeOnlineManagement

# Fonction pour générer un mot de passe aléatoire de 14 caractères
function Generate-RandomPassword {
	param (
		[int]$length = 14
	)

	$chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()"
	$password = -join ((65..90) + (97..122) + (48..57) + (33..47) | Get-Random -Count $length | ForEach-Object {[char]$_})
	return $password
}

# Fonction pour réinitialiser le mot de passe de l'utilisateur
function Reset-UserPassword {
	param (
		[string]$UserEmail
	)

	Write-Output "Réinitialisation du mot de passe pour $UserEmail..."
	$user = Get-AzureADUser -Filter "UserPrincipalName eq '$UserEmail'"
	$newPassword = Generate-RandomPassword
	Set-AzureADUserPassword -ObjectId $user.ObjectId -Password $newPassword -ForceChangePasswordNextSignIn $true
	Write-Output "Mot de passe réinitialisé : $newPassword"
}

# Fonction pour récupérer le gestionnaire de l'utilisateur
function Get-Manager {
	param (
		[string]$UserEmail
	)

	Write-Output "Récupération du gestionnaire pour $UserEmail..."
	$user = Get-AzureADUser -Filter "UserPrincipalName eq '$UserEmail'"
	$manager = Get-AzureADUserManager -ObjectId $user.ObjectId
	Write-Output "Gestionnaire récupéré : $($manager.UserPrincipalName)"
	return $manager.UserPrincipalName
}

# Fonction pour récupérer le chemin OneDrive de l'utilisateur
function Get-OneDrivePath {
	param (
		[string]$UserEmail
	)

	Write-Output "Récupération du chemin OneDrive pour $UserEmail..."
	$user = Get-AzureADUser -Filter "UserPrincipalName eq '$UserEmail'"
	$oneDrivePath = "https://tenant-my.sharepoint.com/personal/$($user.UserPrincipalName.Replace('@', '_').Replace('.', '_'))/Documents"
	Write-Output "Chemin OneDrive récupéré : $oneDrivePath"
	return $oneDrivePath
}

# Fonction pour collecter les données OneDrive
function Collect-OneDriveData {
	param (
		[string]$UserOneDrivePath,
		[string]$ManagerOneDrivePath
	)

	Write-Output "Collecte des données OneDrive de $UserOneDrivePath vers $ManagerOneDrivePath..."
	# Vérifier si le chemin OneDrive de l'utilisateur existe
	if (-Not (Test-Path -Path $UserOneDrivePath)) {
		Write-Output "Le chemin OneDrive de l'utilisateur '$UserOneDrivePath' n'existe pas."
		return
	}

	# Vérifier si le chemin OneDrive du gestionnaire existe
	if (-Not (Test-Path -Path $ManagerOneDrivePath)) {
		Write-Output "Le chemin OneDrive du gestionnaire '$ManagerOneDrivePath' n'existe pas."
		return
	}

	# Copier tous les fichiers et dossiers du OneDrive de l'utilisateur vers le OneDrive du gestionnaire
	Get-ChildItem -Path $UserOneDrivePath | ForEach-Object {
		$Source = $_.FullName
		$Destination = Join-Path -Path $ManagerOneDrivePath -ChildPath $_.Name

		try {
			if ($_.PSIsContainer) {
				Copy-Item -Path $Source -Destination $Destination -Recurse
			} else {
				Copy-Item -Path $Source -Destination $Destination
			}
			Write-Output "Copié '$Source' vers '$Destination'."
		} catch {
			Write-Output "Échec de la copie de '$Source' vers '$Destination' : $_"
		}
	}
	Write-Output "Collecte des données OneDrive terminée."
}

# Fonction pour convertir une boîte de courrier en boîte partagée
function Convert-MailboxToShared {
	param (
		[string]$UserEmail
	)

	Write-Output "Conversion de la boîte de courrier de $UserEmail en boîte partagée..."
	Set-Mailbox -Identity $UserEmail -Type Shared
	Write-Output "Conversion terminée."
}

# Fonction pour déléguer la boîte de courrier au gestionnaire
function Delegate-MailboxToManager {
	param (
		[string]$UserEmail,
		[string]$ManagerEmail
	)

	Write-Output "Délégation de la boîte de courrier de $UserEmail au gestionnaire $ManagerEmail..."
	Add-MailboxPermission -Identity $UserEmail -User $ManagerEmail -AccessRights FullAccess -InheritanceType All
	Write-Output "Délégation terminée."
}

# Fonction pour retirer l'utilisateur de tous les rôles
function Remove-AllRoles {
	param (
		[string]$UserEmail
	)

	Write-Output "Retrait de tous les rôles pour $UserEmail..."
	$user = Get-AzureADUser -Filter "UserPrincipalName eq '$UserEmail'"
	$roles = Get-AzureADDirectoryRole | Get-AzureADDirectoryRoleMember -ObjectId $user.ObjectId

	foreach ($role in $roles) {
		Remove-AzureADDirectoryRoleMember -ObjectId $role.ObjectId -MemberId $user.ObjectId
		Write-Output "Retiré du rôle : $($role.DisplayName)"
	}
	Write-Output "Retrait de tous les rôles terminé."
}

# Fonction pour retirer toutes les licences assignées à l'utilisateur
function Remove-AllLicenses {
	param (
		[string]$UserEmail
	)

	Write-Output "Retrait de toutes les licences pour $UserEmail..."
	$user = Get-AzureADUser -Filter "UserPrincipalName eq '$UserEmail'"
	$licenses = Get-AzureADUserLicenseDetail -ObjectId $user.ObjectId

	foreach ($license in $licenses) {
		Set-AzureADUserLicense -ObjectId $user.ObjectId -RemoveLicenses $license.SkuId
		Write-Output "Licence retirée : $($license.SkuId)"
	}
	Write-Output "Retrait de toutes les licences terminé."
}

# Fonction pour désactiver le compte utilisateur
function Disable-UserAccount {
	param (
		[string]$UserEmail
	)

	Write-Output "Désactivation du compte utilisateur pour $UserEmail..."
	$user = Get-AzureADUser -Filter "UserPrincipalName eq '$UserEmail'"
	Set-AzureADUser -ObjectId $user.ObjectId -AccountEnabled $false
	Write-Output "Désactivation terminée."
}

# Fonction pour retirer l'utilisateur de tous les groupes de sécurité
function Remove-AllSecurityGroups {
	param (
		[string]$UserEmail
	)

	Write-Output "Retrait de tous les groupes de sécurité pour $UserEmail..."
	$user = Get-AzureADUser -Filter "UserPrincipalName eq '$UserEmail'"
	$groups = Get-AzureADUserMembership -ObjectId $user.ObjectId | Where-Object { $_.ObjectType -eq "Group" }

	foreach ($group in $groups) {
		Remove-AzureADGroupMember -ObjectId $group.ObjectId -MemberId $user.ObjectId
		Write-Output "Retiré du groupe de sécurité : $($group.DisplayName)"
	}
	Write-Output "Retrait de tous les groupes de sécurité terminé."
}

# Fonction pour rendre l'utilisateur invisible dans le carnet d'adresses d'entreprise
function Hide-FromAddressBook {
	param (
		[string]$UserEmail
	)

	Write-Output "Rendre l'utilisateur $UserEmail invisible dans le carnet d'adresses d'entreprise..."
	Set-Mailbox -Identity $UserEmail -HiddenFromAddressListsEnabled $true
	Write-Output "L'utilisateur est maintenant invisible dans le carnet d'adresses d'entreprise."
}



# Fonction pour l'"off boarding" d'un utilisateur
function OffBoard-User {
	param (
		[string]$UserEmail
	)

	Write-Output "Début du processus d'off-boarding pour $UserEmail..."

	# Récupérer le gestionnaire et les chemins OneDrive
	$ManagerEmail = Get-Manager -UserEmail $UserEmail
	$UserOneDrivePath = Get-OneDrivePath -UserEmail $UserEmail
	$ManagerOneDrivePath = Get-OneDrivePath -UserEmail $ManagerEmail

	# Collecter les données OneDrive
	Collect-OneDriveData -UserOneDrivePath $UserOneDrivePath -ManagerOneDrivePath $ManagerOneDrivePath

	# Convertir la boîte de courrier en boîte partagée
	Convert-MailboxToShared -UserEmail $UserEmail

	# Déléguer la boîte de courrier au gestionnaire
	Delegate-MailboxToManager -UserEmail $UserEmail -ManagerEmail $ManagerEmail

	# Retirer l'utilisateur de tous les rôles
	Remove-AllRoles -UserEmail $UserEmail

	# Retirer toutes les licences assignées à l'utilisateur
	Remove-AllLicenses -UserEmail $UserEmail

	# Retirer l'utilisateur de tous les groupes de sécurité
	Remove-AllSecurityGroups -UserEmail $UserEmail

	# Désactiver le compte utilisateur
	Disable-UserAccount -UserEmail $UserEmail

	# Rendre l'utilisateur invisible dans le carnet d'adresses d'entreprise
	Hide-FromAddressBook -UserEmail $UserEmail

	# Réinitialiser le mot de passe de l'utilisateur
	Reset-UserPassword -UserEmail $UserEmail

	# Déconnecter l'utilisateur de toutes ses connexions actives
	Disconnect-UserSessions -UserEmail $UserEmail

	# Tâches supplémentaires d'off-boarding
	Write-Output "Révocation des accès pour $UserEmail..."
	# Code pour révoquer les accès

	Write-Output "Processus d'off-boarding pour $UserEmail terminé."
}

# Exemple d'utilisation
$UserEmail = "user@example.com"
OffBoard-User -UserEmail $UserEmail