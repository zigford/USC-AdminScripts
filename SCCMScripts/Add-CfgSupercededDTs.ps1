<#
.SYNOPSIS
    Supercede many older apps with 1 script
.DESCRIPTION
    Get all the deployment types base on an app search and add all their dt's as superceded to a new app
.PARAMETER SiteCode
    Specify the sitecode of your Config Manager site
.PARAMETER SiteServer
    Specify the hostname of your Config Manager provider to connect to
.PARAMETER NewAppName
    Specify the app model name of the application which will supercede old apps and their deployment types
.PARAMETER Filter
    Specify a filter to find apps with deployment types to supercede
.EXAMPLE
    Add-CfgSupercededDTs -SiteCode SC0 -SiteServer wsn-cfgmgr01 -NewAppName 'Power Bi 2.57.3' -Filter 'Power Bi *'
.NOTES
    notes
.LINK
    online help
#>

[CmdLetBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
Param(
    [Parameter(Mandatory=$True)]$SiteCode,
    [Parameter(Mandatory=$True)]$SiteServer,
    [Parameter(Mandatory=$True)]$NewAppName,
    [Parameter(Mandatory=$True)]$Filter
)
# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer @initParams
}

# Set the current location to be the site code.
Push-Location
Set-Location "$($SiteCode):\" @initParams

$App = Get-CMApplication -Name $NewAppName
$SupercededApps = Get-CMApplication -Name $Filter | Where-Object { $_.LocalizedDisplayName -ne $App.LocalizedDisplayName }
ForEach ($SupercededApp in $SupercededApps) {
    $DTs = $SupercededApp | Get-CMDeploymentType
    ForEach ($DT in $DTs) {
        Write-Verbose "Adding DT $($DT.LocalizedDisplayName) as superceded"
        If ($PSCmdlet.ShouldProcess("$NewAppName", "Adding $($DT.LocalizedDisplayName)")) {
            Add-CMDeploymentTypeSupersedence `
                -SupersedingDeploymentType ($App | Get-CMDeploymentType) `
                -SupersededDeploymentType $DT `
                -IsUninstall $True
        }
    }
}
Pop-Location