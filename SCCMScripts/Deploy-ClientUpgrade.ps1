[CmdLetBinding(SupportsShouldProcess)]
Param()

$SiteCode = 'SC1'
$SiteServer = 'wsp-configmgr01'

if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
}

if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer
}

# Set the current location to be the site code.
Push-Location
Set-Location "$($SiteCode):\"

$Collections = Get-CMCollection -Name '*Windows Server Patch*Tues*am'
$ClientUpgradeSettings = @{
    StandardProgram = [switch]$True
    PackageName = 'Configuration Manager Client Upgrade'
    ProgramName = 'Configuration Manager agent silent upgrade'
    DeployPurpose = 'Required'
    RerunBehavior = 'AlwaysRerunProgram'
    SoftwareInstallation = $True
    FastNetworkOption = 'DownloadContentFromDistributionPointAndRunLocally'
    SlowNetworkOption = 'DownloadContentFromDistributionPointAndLocally'
}

function Get-Tuesday { 
    <#  
    .SYNOPSIS   
    Get the Patch Tuesday of a month 
    .PARAMETER month 
    The month to check
    .PARAMETER year 
    The year to check
    .EXAMPLE  
    Get-PatchTue -month 6 -year 2015
    .EXAMPLE  
    Get-PatchTue June 2015
    #> 
    [CmdLetBinding()]    
    param( 
        [int]$Occurring=1,
        [int]$Month,
        [int]$Year
    ) 
    If (-Not $Month) { $Month = Get-Date -Format 'MM' }
    If (-Not $Year)  { $Year  = Get-Date -Format 'yyyy'}
    $firstdayofmonth = [datetime] ([string]$Month + "/1/" + [string]$Year)
    $Tuesday = (0..30 | ForEach-Object {$firstdayofmonth.adddays($_) } | Where-Object {$_.dayofweek -like "Tue*"})[$Occurring -1 ]
    If ($Tuesday -gt (Get-Date)) {
        $Tuesday
    } else {
        If ($Month -eq '12') {
            Get-Tuesday -Occurring $Occurring -Month 1 -Year ($Year + 1)
        } else {
            Get-Tuesday -Occurring $Occurring -Month ($Month + 1)
        }
    }
}

function Get-Schedule {
    <#Work out a schedule based on a collection name#>
    Param($CollectionName)
    $WhichTuesday = Switch -Regex ($CollectionName) {
        '.*1st.*' {1}
        '.*2nd.*' {2}
        '.*3rd.*' {3}
        '.*4th.*' {4}
    }
    $ScheduleTime = Get-date "$(Get-date (Get-Tuesday -Occurring $WhichTuesday) -format 'dd/MM/yyyy') 5am"
    New-CMSchedule -Start $ScheduleTime -Nonrecurring -WhatIf:$False
}

ForEach ($Collection in $Collections) {
    $Schedule = Get-Schedule $Collection.Name
    Write-Verbose "Testing $($Collection.Name)"
    New-CMPackageDeployment @ClientUpgradeSettings `
        -CollectionID $Collection.CollectionId `
        -Schedule $Schedule
}
Pop-Location