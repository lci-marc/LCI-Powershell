<#
.SYNOPSIS
	Supprime tous les utilisateurs d'une unité organisationnelle Active Directory spécifiée.

.DESCRIPTION
	Ce script permet de supprimer en masse tous les utilisateurs contenus dans une unité
	organisationnelle (OU) Active Directory. Il inclut des mécanismes de sécurité comme
	la confirmation utilisateur et la journalisation détaillée des opérations.

.PARAMETER OUPath
	Chemin LDAP complet de l'unité organisationnelle.
	Exemple: "OU=Utilisateurs,DC=entreprise,DC=local"

.PARAMETER Force
	(Optionnel) Si spécifié, le script s'exécute sans demander de confirmation.
	À utiliser avec précaution.

.PARAMETER LogPath
	(Optionnel) Chemin du fichier de journal.
	Par défaut: "C:\Logs\DeleteUsers_[DATE_HEURE].log"

.EXAMPLE
	.\Delete-ADUsers.ps1 -OUPath "OU=Temporaires,DC=entreprise,DC=local"
	Supprime tous les utilisateurs de l'OU "Temporaires" après confirmation.

.EXAMPLE
	.\Delete-ADUsers.ps1 -OUPath "OU=Stagiaires,DC=entreprise,DC=local" -Force
	Supprime tous les utilisateurs de l'OU "Stagiaires" sans demander de confirmation.

.EXAMPLE
	.\Delete-ADUsers.ps1 -OUPath "OU=Consultants,DC=entreprise,DC=local" -LogPath "C:\Delete_Consultants.log"
	Supprime les utilisateurs avec un fichier de journal personnalisé.

.NOTES
	Nom du fichier    : Delete-ADUsers.ps1
	Prérequis         : - Module ActiveDirectory
						- Droits d'administration sur l'Active Directory
						- Windows PowerShell 5.1 ou supérieur
	Version           : 1.0
	Auteur           : [Votre Nom]
	Date de création  : 14/02/2025

	Historique des modifications :
	1.0 - Version initiale

.LINK
	https://learn.microsoft.com/fr-fr/powershell/module/activedirectory/

.OUTPUTS
	- Affichage console des opérations en cours
	- Fichier journal détaillé

.COMPONENT
	Active Directory

.FUNCTIONALITY
	Active Directory Management
#>

# Requiert le module Active Directory
Import-Module ActiveDirectory

# Paramètres du script
param(
	[Parameter(Mandatory=$true)]
	[string]$OUPath,
	
	[Parameter(Mandatory=$false)]
	[switch]$Force,
	
	[Parameter(Mandatory=$false)]
	[string]$LogPath = "C:\Logs\DeleteUsers_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# Fonction pour écrire dans le journal
function Write-Log {
	param($Message)
	
	$LogMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
	Write-Host $LogMessage
	Add-Content -Path $LogPath -Value $LogMessage
}

# Création du dossier de logs s'il n'existe pas
$LogDir = Split-Path $LogPath -Parent
if (-not (Test-Path $LogDir)) {
	New-Item -ItemType Directory -Path $LogDir | Out-Null
}

try {
	# Vérification que l'OU existe
	if (-not (Get-ADOrganizationalUnit -Identity $OUPath -ErrorAction SilentlyContinue)) {
		throw "L'unité organisationnelle spécifiée n'existe pas: $OUPath"
	}

	# Récupération de la liste des utilisateurs
	$Users = Get-ADUser -Filter * -SearchBase $OUPath -Properties Name, SamAccountName
	$UserCount = ($Users | Measure-Object).Count

	Write-Log "Nombre d'utilisateurs trouvés dans l'OU: $UserCount"

	if ($UserCount -eq 0) {
		Write-Log "Aucun utilisateur à supprimer dans cette OU."
		return
	}

	# Demande de confirmation si -Force n'est pas utilisé
	if (-not $Force) {
		$Confirmation = Read-Host "Êtes-vous sûr de vouloir supprimer $UserCount utilisateurs de l'OU? (O/N)"
		if ($Confirmation -ne "O") {
			Write-Log "Opération annulée par l'utilisateur."
			return
		}
	}

	# Suppression des utilisateurs
	$SuccessCount = 0
	$ErrorCount = 0

	foreach ($User in $Users) {
		try {
			Remove-ADUser -Identity $User.SamAccountName -Confirm:$false
			Write-Log "Utilisateur supprimé avec succès: $($User.Name) ($($User.SamAccountName))"
			$SuccessCount++
		}
		catch {
			Write-Log "ERREUR lors de la suppression de l'utilisateur $($User.Name): $_"
			$ErrorCount++
		}
	}

	# Résumé final
	Write-Log "Opération terminée:"
	Write-Log "- Utilisateurs supprimés avec succès: $SuccessCount"
	Write-Log "- Erreurs rencontrées: $ErrorCount"
}
catch {
	Write-Log "ERREUR CRITIQUE: $_"
	throw
}
finally {
	Write-Log "Script terminé. Journal sauvegardé dans: $LogPath"
}