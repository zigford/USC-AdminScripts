[CmdLetBinding()]
Param([Parameter(Mandatory=$True)]$TaskSequenceName,[Switch]$Whatif)
#
# Press 'F5' to run this script. Running this script will load the ConfigurationManager
# module for Windows PowerShell and will connect to the site.
#
# This script was auto-generated at '20/12/2017 2:20:08 PM'.

# Uncomment the line below if running in an environment where script signing is 
# required.
#Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Site configuration
$SiteCode = "SC1" # Site code 
$ProviderMachineName = "wsp-configmgr01.usc.internal" # SMS Provider machine name

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
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}
Push-Location
# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

$TaskSequence = Get-CMTaskSequence -Name $TaskSequenceName
$Deployments = @{
    CollectionName = 'Mandatory Shared'
    TaskSequencePackageId = $TaskSequence.PackageID
    DeployPurpose = 'Required'
    Availability = 'MediaAndPxe'
    Schedule = (New-CMSchedule -Nonrecurring -Start (Get-Date))
    ReRunBehavior = 'RerunIfFailedPreviousAttempt'
    DeploymentOption = 'RunFromDistributionPoint'
},@{
    CollectionName = 'Mandatory NonShared'
    TaskSequencePackageId = $TaskSequence.PackageID
    DeployPurpose = 'Required'
    Availability = 'MediaAndPxe'
    Schedule = (New-CMSchedule -Nonrecurring -Start (Get-Date))
    ReRunBehavior = 'RerunIfFailedPreviousAttempt'
    DeploymentOption = 'RunFromDistributionPoint'
},@{
    CollectionName = 'Mandatory NonShared (No365Lic)'
    TaskSequencePackageId = $TaskSequence.PackageID
    DeployPurpose = 'Required'
    Availability = 'MediaAndPxe'
    Schedule = (New-CMSchedule -Nonrecurring -Start (Get-Date))
    ReRunBehavior = 'RerunIfFailedPreviousAttempt'
    DeploymentOption = 'RunFromDistributionPoint'
},@{
    CollectionName = 'Optional Shared'
    TaskSequencePackageId = $TaskSequence.PackageID
    DeployPurpose = 'Available'
    Availability = 'ClientsMediaAndPxe'
    DeploymentOption = 'RunFromDistributionPoint'
},@{
    CollectionName = 'All Unknown Computers'
    TaskSequencePackageId = $TaskSequence.PackageID
    DeployPurpose = 'Available'
    Availability = 'ClientsMediaAndPxe'
    DeploymentOption = 'RunFromDistributionPoint'
},@{
    CollectionName = 'Optional Image (Win10)'
    TaskSequencePackageId = $TaskSequence.PackageID
    DeployPurpose = 'Available'
    Availability = 'ClientsMediaAndPxe'
    DeploymentOption = 'RunFromDistributionPoint'
}

$Deployments | ForEach-Object {
    Write-Verbose ("Creating deployment of {0} to {1} as {2}" -f $TaskSequenceName,$_.CollectionName,$_.DeployPurpose)
    $Object = [PSCustomObject]@{
        'TaskSequence' = $TaskSequenceName
        'CollectionName' = $_.CollectionName
        'Purpose' = $_.DeployPurpose
        'Success' = $True
    }
    If (New-CMTaskSequenceDeployment @_ -ErrorAction SilentlyContinue -Whatif:$Whatif) {
        $Object.Success = $True
    } else {
        $Object.Success = $False
    }
    $Object
}
Pop-Location