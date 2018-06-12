
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

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

Import-Module D:\dev\zigford\USC-SCCM
Connect-CfgSiteServer
$ExcludedLabs = 'OPACS',
    '$_.*',
    'All Managed Labs',
    'Info Commons',
    'CB Infocommons All',
    'ServiceDesk LoanPool',
    'Student Citrix Laptops',
    'BT TI Masters',
    'CB H.1.07 Lab Indigenous Services',
    'CB L.1.04 Infocommons',
    'CB L.1.10 Infocommons',
    'CB L.1.14 Infocommons',
    'CB N.1.04 Infocommons',
    'Laptops_ENS253_S1_2018_Till_Week4',
    '^Presentation Spaces.*'

#$Labs = Get-CfgCollectionsByFolder -FolderName 'Managed Labs'
$NewLabList = $Labs
$ExcludedLabs | %{$mstr=$_; $NewLabList = $NewLabList | ? CollectionName -NotMatch $mstr}
$NewSortedLabList = @()
$Deprioritiezed= @()
$NewLabList | %{If ($_.CollectionName -match 'InfoCommons') {$NewSortedLabList+=$_} else {$Deprioritiezed+=$_}}
$NewSortedLabList+=$Deprioritiezed
$NewLabList = $NewSortedLabList

$AugmentDay = 0
$ScheduleDay = (Get-Date (Get-Date 1am)).AddDays($AugmentDay)
$LabsPerDay = 3
$StartingLab = 0
$Obj = For ($LabBlock=$StartingLab; $LabBlock -le ($NewLabList.count - 1); $LabBlock+=$LabsPerDay) {
    $AugmentDay++
    $ScheduleDay = (Get-Date (Get-Date 1am)).AddDays($AugmentDay)
    For ($Lab=$LabBlock; $Lab -lt $LabBlock+$LabsPerDay -and $Lab -le ($NewLabList.Count -1); $Lab++) {
        [PSCustomObject]@{
            Lab = $NewLabList[$Lab].CollectionName
            Schedule = $ScheduleDay
            MemberCount = (Get-CMCollection -Name $NewLabList[$Lab].CollectionName).MemberCount
        }
    } 
}

# Schedule all bios Upgrades
$Obj | %{
    $Sched = New-CMSchedule -Start $_.Schedule -RecurInterval Days -RecurCount 1
    New-CMTaskSequenceDeployment -TaskSequencePackageId 'SC1006F3' `
        -DeployPurpose Required -Availability Clients `
        -Schedule $Sched -RerunBehavior AlwaysRerunProgram `
        -SoftwareInstallation $False `
        -ShowTaskSequenceProgress $False `
        -DeploymentOption DownloadAllContentLocallyBeforeStartingTaskSequence `
        -AvailableDateTime $_.Schedule -SendWakeupPacket $True `
        -CollectionName $_.Lab
}

#Pick a machine for each target and add it to a pilot
$Obj | %{
    $RandomDevice = Get-CMDevice -CollectionName $_.Lab | Get-Random -Count 1
    Add-CMDeviceCollectionDirectMembershipRule -CollectionId SC100CC1 -ResourceId $RandomDevice.ResourceID
}