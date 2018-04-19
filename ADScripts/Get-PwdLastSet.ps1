<#
    .SYNOPSIS
    Get the date an account's password was last updated

    .DESCRIPTION
    Query AD for the account's PwdLastSet Attribute and convert it to a powershell date type

    .PARAMETER Identity
    The SamAccountName or Username of the account to query

    .EXAMPLE
    PS> .\Get-PwdLastSet.ps1 -Id jpharris

    SamAccoutName  LastSet
    -------------  -------
    jpharris       9/01/2018 10:08:26 AM

    .EXAMPLE
    PS> Get-Content C:\UserList.txt | .\Get-PwdLastSet.ps1

    SamAccountName  LastSet
    --------------  -------
    jpharris        9/01/2018 10:08:26 AM 
    jphelan         20/12/2010 4:00:24 PM 
    jphilli1        8/05/2017 1:12:01 PM  
    jphillip        24/04/2016 8:56:31 AM 

    .EXAMPLE
    PS> .\Get-PwdLastSet.ps1 -Filter {samaccountname -like 'jph*'}

    SamAccountName LastSet               
    -------------- -------               
    jph001         25/07/2013 1:21:14 PM 
    jph002         24/04/2016 9:51:57 AM 
    jph003         6/02/2011 10:19:54 AM 
    jph009         6/02/2011 10:49:44 AM 
    jph010         17/03/2014 10:16:48 PM

    .NOTES
    Author: Jesse Harris
    Date: 19/04/2018
#>

[CmdLetBinding()]
Param(
    [Parameter(
        ParameterSetName = "ID",
        ValueFromPipeline=$True)]$Identity,
    [Parameter(
        ParameterSetName = "Filter")]$Filter
)

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