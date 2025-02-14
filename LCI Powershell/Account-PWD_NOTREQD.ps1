# Script pour lister les comptes AD avec l'attribut PWD_NOTREQD
# Nécessite le module Active Directory

# Import du module Active Directory
Import-Module ActiveDirectory

# Initialisation des variables
$date = Get-Date -Format "yyyy-MM-dd_HH-mm"
$outputFile = "C:\Temp\AD_PWD_NOTREQD_Accounts_$date.csv"

# Création du dossier de sortie si nécessaire
if (-not (Test-Path "C:\Temp")) {
	New-Item -ItemType Directory -Path "C:\Temp"
}

try {
	# Récupération des comptes avec l'attribut PWD_NOTREQD
	$accounts = Get-ADUser -Filter * -Properties `
		SamAccountName,
		DisplayName,
		UserPrincipalName,
		Description,
		whenCreated,
		LastLogonDate,
		PasswordLastSet,
		UserAccountControl,
		Enabled,
		DistinguishedName | 
		Where-Object { $_.UserAccountControl -band 0x0020 }

	# Préparation des données pour l'export
	$exportData = $accounts | Select-Object `
		@{Name='Nom du compte';Expression={$_.SamAccountName}},
		@{Name='Nom complet';Expression={$_.DisplayName}},
		@{Name='UPN';Expression={$_.UserPrincipalName}},
		@{Name='Description';Expression={$_.Description}},
		@{Name='Date de création';Expression={$_.whenCreated}},
		@{Name='Dernière connexion';Expression={$_.LastLogonDate}},
		@{Name='Dernier changement MDP';Expression={$_.PasswordLastSet}},
		@{Name='UserAccountControl';Expression={$_.UserAccountControl}},
		@{Name='Compte actif';Expression={$_.Enabled}},
		@{Name='Chemin AD';Expression={$_.DistinguishedName}}

	# Export en CSV
	$exportData | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

	# Affichage des résultats
	Write-Host "Nombre de comptes trouvés : $($accounts.Count)" -ForegroundColor Green
	Write-Host "Rapport exporté vers : $outputFile" -ForegroundColor Green

	# Affichage du résumé
	Write-Host "`nRésumé des comptes :" -ForegroundColor Cyan
	$accounts | Format-Table -Property SamAccountName, DisplayName, LastLogonDate -AutoSize

} catch {
	Write-Host "Erreur lors de l'exécution : $_" -ForegroundColor Red
}

# Affichage des statistiques
Write-Host "`nStatistiques :" -ForegroundColor Yellow
Write-Host "Comptes actifs : $($accounts | Where-Object {$_.Enabled} | Measure-Object | Select-Object -ExpandProperty Count)"
Write-Host "Comptes désactivés : $($accounts | Where-Object {-not $_.Enabled} | Measure-Object | Select-Object -ExpandProperty Count)"