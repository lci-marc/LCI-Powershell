# Define the user account and target OU
$userAccount = "username"
$targetOU = "OU=DisabledUsers,DC=yourdomain,DC=com"

# Import the Active Directory module
Import-Module ActiveDirectory

# Disable the user account
Disable-ADAccount -Identity $userAccount

# Move the user account to the target OU
Move-ADObject -Identity (Get-ADUser -Identity $userAccount).DistinguishedName -TargetPath $targetOU

# Remove all group memberships except for Domain Users
$groups = Get-ADUser -Identity $userAccount -Property MemberOf | Select-Object -ExpandProperty MemberOf
foreach ($group in $groups) {
    if ($group -notlike "*Domain Users*") {
        Remove-ADGroupMember -Identity $group -Members $userAccount -Confirm:$false
    }
}

Write-Output "User $userAccount has been offboarded successfully."

<#
Explanation:

1. Define the user account and target OU: Replace "username" with the actual username and "OU=DisabledUsers,DC=yourdomain,DC=com" with the distinguished name of your target OU.
2. Import the Active Directory module: Ensures the necessary cmdlets are available.
3. Disable the user account: Disables the specified user account.
4. Move the user account to the target OU: Moves the user account to the specified OU.
5. Remove all group memberships except for Domain Users: Iterates through the user's group memberships and removes them, except for the "Domain Users" group.

Feel free to customize the script further to meet your specific needs. If you have any questions or need additional modifications, I'm here to help!
#>