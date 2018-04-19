[CmdLetBinding()]
Param(
    [Parameter(
        ParameterSetName = "ID",
        ValueFromPipeline=$True)]$Identity,
    [Parameter(
        ParameterSetName = "Filter")]$Filter
)

<#
.SYNOPSIS
Get the date an account's password was last updated

.DESCRIPTION
Query AD for the account's PwdLastSet Attribute and convert it to a powershell date type

.PARAMETERS Identity
The SamAccountName or Username of the account to query

.EXAMPLE
PS> Get-PwdLastSet -Id jpharris

SamAccoutName  LastSet
-------------  -------
jpharris       Tuesday Jan 4 2018

.NOTES
Author: Jesse Harris
Date: 19/04/2018

#>

Begin {
    If (Get-Module -ListAvailable ActiveDirectory -EA SilentlyContinue) {
        Import-Module ActiveDirectory
    } Else {
        Write-Error "Unable to find Active Directory module"
    }
    If ($Filter) {
        $Identity = Get-ADUser -Filter $Filter -Properties PwdLastSet
    }
}

Process {
    ForEach ($Id in $Identity) {
        If (-Not $Id.PwdLastSet) {
            $Id = Get-ADUser -Identity $Id -Properties PwdLastSet
        }
        [PSCustomObject]@{
            'SamAccountName' = $Id.SamAccountName
            'LastSet' = [datetime]::fromFileTime($Id.pwdLastSet)
        }
    }
}