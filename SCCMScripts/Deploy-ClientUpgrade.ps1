[CmdLetBinding(SupportsShouldProcess)]
Param(
        [Parameter(Mandatory=$True)]$CollectionFilter,
        [ValidateSet(
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
            'Sunday'
        )]$DayOfWeek='Friday'
     )

$SiteCode = 'SC1'
$SiteServer = 'wsp-configmgr01'

if($Null -eq (Get-Module ConfigurationManager)) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
}

if($Null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer
}

# Set the current location to be the site code.
Push-Location
Set-Location "$($SiteCode):\"

$Collections = Get-CMCollection -Name $CollectionFilter
If (-Not ($Collections)) {
    throw "No collections found with filter"
}

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

function Get-DayOfWeek {
    <#
    .SYNOPSIS
    Get the Friday of a month
    .PARAMETER month
    The month to check
    .PARAMETER year
    The year to check
    .EXAMPLE
    Get-Friday -month 6 -year 2015
    .EXAMPLE
    Get-Friday June 2015
    #>
    [CmdLetBinding()]
    param(
        [int]$Occurring=1,
        [int]$Month,
        [int]$Year,
        [string]$DayOfWeek
    )
    If (-Not $Month) { $Month = Get-Date -Format 'MM' }
    If (-Not $Year)  { $Year  = Get-Date -Format 'yyyy'}
    $firstdayofmonth = [datetime] ([string]$Month + "/1/" + [string]$Year)
    $Day = (0..30 | ForEach-Object {$firstdayofmonth.adddays($_) } | Where-Object {$_.dayofweek -eq $DayOfWeek})[$Occurring -1 ]
    If ($Day -gt (Get-Date)) {
        $Day
    } else {
        If ($Month -eq '12') {
            $Year = $Year + 1
            $Month = 1
        } else {
            $Month = $Month + 1
        }
        Get-DayOfWeek -Occurring $Occurring `
            -Month $Month -Year $Year `
            -DayOfWeek $DayOfWeek
    }
}

function Get-Schedule {
    <#Work out a schedule based on a collection name#>
    Param($CollectionName)
    $WhichDay = Switch -Regex ($CollectionName) {
        '.*1st.*' {1}
        '.*2nd.*' {2}
        '.*3rd.*' {3}
        '.*4th.*' {4}
    }
    $ScheduleTime = Get-date "$(Get-date (Get-DayOfWeek -Occurring $WhichDay) -format 'dd/MM/yyyy') 5am"
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
