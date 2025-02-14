<#
An Offboarding Script for On-Prem Active Directory
March 06, 2024
A while back I wrote an Offboarding Script that I still maintain.  It has saved me a ton of time throughout the years.  

This code does several things, So let's go through the steps.

Step 1. Import the Active Directory (AD) module into Powershell.
Step 2. Prompts the user to enter the username of the user being offboarded.
Step 3. Gets information about that user and sets those objects to variables.
Step 4. Disables the account
Step 5. Generates a random password and resets the user's password to the new randomly generated password.
Step 6. Sets one of the extension attributes to today's date for use in a later account deletion script.
Step 7. Gets the OU the user resides in and adds that information to the log file generated at the end of this script.
Step 8. Gets the permissions, security groups, and distribution lists the user was a member of and adds them to the log file.
Step 9. Clears all user permissions.
Step 10. Moves the account to the Terminated OU.
Step 11. Imports the exchange Snap-in for use in changing mailbox settings.
Step 12. Removes any previously configured forwarding rules
Step 13. Sets up forwarding to the user's Manager's inbox.
Step 14. Sets an Out-of-office message for the user's mailbox.
Step 15. Begins exporting the user's PST file to a backup server.
Step 16. Disables all Exchange and OWA settings
Step 17. If all steps are successful, the script sends an email to IT, HR, and the User's Manager.
Step 17.5 If unsuccessful, the script sends and email containing the error message to IT for further investigation.
#>


$date = [datetime]::Today.ToString('dd-MM-yyyy')
$todaysDate = get-date -Format 'MM-dd-yyy'
# Un-comment the following if PowerShell isn't already set up to do this on its own
Import-Module ActiveDirectory

 Blank the console
 Clear-Host

Write-Host "Offboard a user

"

<# --- Active Directory account dispensation section --- #>

$sam = Read-Host 'Account name to disable'

# Get the properties of the account and set variables
$user = Get-ADuser $sam -properties canonicalName, distinguishedName, displayName, mailNickname
$dn = $user.distinguishedName
$cn = $user.canonicalName
$din = $user.displayName
$UserAlias = $user.mailNickname
$UserManager = (Get-ADUser (Get-ADUser $sam -Properties manager).manager -Properties mail).mail
$AutoReply = "I am no longer with NAPA Transportation. If you need assistance please reach out to " + $UserManager + "."

# Path building
$path1 = "\\fileserver\IT Share\Offboarding logs\"
$path2 = "-AD-DisabledUserPermissions.csv"
$pathFinal = $path1 + $din + $path2

Try {

        # Disable the account
        Disable-ADAccount $sam
        Write-Host ($din + "'s Active Directory account is disabled.")

        #Generates a random 20 character password and converts it to plaintext for use in this script.
        $Passwd = -join ((48..122) | Get-Random -Count 20 | ForEach-Object{[char]$_})
        $PasswdSecStr = ConvertTo-SecureString $passwd -AsPlainText -Force

        #Resets user's password
        Set-ADAccountPassword -Identity "$sam" -NewPassword $PasswdSecStr -Reset
        Write-Host ($din + "'s Active Directory password has been changed.")

        #set extensionAttribute4 to todays date for use when deleting the account
        Set-ADUser -Identity "$sam" -Add @{extensionAttribute10= "$todaysDate"}

        # Add the OU path where the account originally came from to the description of the account's properties
        Set-ADUser $dn -Description ("Moved from: " + $cn + " - on $date")
        Write-Host ($din + "'s Active Directory account path saved.")

        # Get the list of permissions (group names) and export them to a CSV file for safekeeping
        $groupinfo = get-aduser $sam -Properties memberof | select name, 
        @{ n="GroupMembership"; e={($_.memberof | foreach{get-adgroup $_}).name}}
        $count = 0
        $arrlist =  New-Object System.Collections.ArrayList
    do{
        $null = $arrlist.add([PSCustomObject]@{
        # Name = $groupinfo.name
        GroupMembership = $groupinfo.GroupMembership[$count]
        })
        $count++
    }until($count -eq $groupinfo.GroupMembership.count)

        $arrlist | select groupmembership |
        convertto-csv -NoTypeInformation |
        select -Skip 1 |
        out-file $pathFinal
        Write-Host ($din + "'s Active Directory group memberships (permissions) exported and saved to " + $pathFinal)

        # Strip the permissions from the account
        Get-ADUser $User -Properties MemberOf | Select -Expand MemberOf | %{Remove-ADGroupMember $_ -member $User -Confirm:$false}
        Write-Host ($din + "'s Active Directory group memberships (permissions) stripped from account")

        # Move the account to the Disabled Users OU
        Move-ADObject -Identity $dn -TargetPath "Ou=NAPA_Terminated,OU=NAPA Users,DC=napa,DC=local"
        Write-Host ($din + "'s Active Directory account moved to 'NAPA_Terminated' OU")

        <# --- Exchange email account dispensation section --- #>

        # Import the Exchange snapin (assumes desktop PowerShell)
        if (!(Get-PSSnapin | where {$_.Name -eq "Microsoft.Exchange.Management.PowerShell.SnapIn"})) { 

	    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://MAILSERVER.napa.local/Powershell -Authentication Kerberos
        Import-PSSession $Session -DisableNameChecking -AllowClobber

}
        #remove any previously configured forwarding rules
        Set-Mailbox -Identity "$sam" -forwardingsmtpaddress $null
        Set-Mailbox -Identity "$sam" -forwardingaddress $null

        #configure forwarding to Supervisor's email address
        Set-Mailbox -Identity "$sam" -forwardingsmtpaddress  $UserManager -DeliverToMailboxAndForward $true

        #set Out of Office on the user's mailbox.
        Set-MailboxAutoReplyConfiguration -Identity "$sam" -AutoReplyState Enabled -InternalMessage $AutoReply -ExternalMessage $AutoReply

        # Loop flag variables
        $Go1 = 0
        $Go2 = 0
        $Go3 = 0
        $GoDone = 0

       Function Save-File ([string]$initialDirectory) {

	    $PresAdmin = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
	    $AdminCheck = Get-ManagementRoleAssignment -RoleAssignee "$PresAdmin" -Role "Mailbox Import Export" -RoleAssigneeType user
	    If ($AdminCheck -eq $Null) {New-ManagementRoleAssignment -Role "Mailbox Import Export" -User $PresAdmin}

	    $MailBackupFileDate = (get-date -UFormat %b-%d-%Y_%I.%M.%S%p)
	    $MailBackupInitialPath = "\\backup1\oldemployeeemailpst\"
	    $MailBackupFileName = $sam+$MailBackupFileDate+".pst"

        Add-Type -AssemblyName System.Drawing
        Add-Type -AssemblyName System.Windows.Forms
    
        $OpenFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $OpenFileDialog.initialDirectory = $MailBackupInitialPath
        $OpenFileDialog.filter = "PST (*.pst)| *.pst"
	    $OpenFileDialog.FileName = $MailBackupFileName
        $OpenFileDialog.ShowDialog() | Out-Null

        return $OpenFileDialog.filename

}

        #Export .pst file
        $MailBackupFile = Save-File
        New-MailboxExportRequest -Mailbox $sam -FilePath $MailBackupFile

        #disable Exchange settings (OWA/ActiveSync/etc.)
        Set-CasMailbox -Identity "$sam" -OWAEnabled $false -ActiveSyncEnabled $false -PopEnabled $false -ImapEnabled $false -OWAforDevicesEnabled $False


$SuccessMailParams = @{
            To         = 'IT@napatran.com','HR@napatran.com', ($UserManager)
            From       = 'IT@napatran.com'
            SmtpServer = 'mail.napatran.com'
            Subject    = ($din + ' was sucessfully offboarded') 
            Body       = ( "The following changes have been made to the user's account:`
                                Active Directory account is disabled.`
                                The User's email has been forwarded to their Manager.`
                                An automatic reply has been enabled of the user's mailbox.`
                                Password has been changed.`
                                Account path saved.`
                                Group memberships (permissions) exported and saved to \\fileserver\IT Share\Offboarding logs\`
                                Group memberships (permissions) stripped from account.`
                                Account moved to NAPA_Terminated OU`
                                Mailbox .pst was exported and saved to Backup1.`
                                Exchange settings were disabled (ActiveSync/OWA/etc.).")
                       }
            Send-MailMessage @SuccessMailParams
}
Catch
{
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Send-MailMessage -From 'IT@napatran.com' -To 'IT@napatran.com' -Subject "EmployeeOffboarding Script has failed to disable a user account" -SmtpServer 'mail.napatran.com' -Body "The error message is: '$ErrorMessage'"
    Break
}
