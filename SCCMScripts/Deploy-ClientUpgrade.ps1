function New-ClientUpgrade {
    [CmdLetBinding(SupportsShouldProcess)]
    Param(
            [Parameter(Mandatory=$True)]$CollectionFilter,
            [DateTime]$DateTime
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

    function Get-Schedule {
        <#Work out a schedule based on a collection name#>
        Param($CollectionName,$DateTime)
        New-CMSchedule -Start $DateTime -Nonrecurring -WhatIf:$False -Confirm:$False
    }

    ForEach ($Collection in $Collections) {
        $Schedule = Get-Schedule $Collection.Name -DateTime $DateTime
        Write-Verbose "Testing $($Collection.Name)"
        If ($PSCmdLet.ShouldProcess($Collection.Name,"client upgrade deployment at $($Schedule.StartTime)")) {
            New-CMPackageDeployment @ClientUpgradeSettings `
                -CollectionID $Collection.CollectionId `
                -Schedule $Schedule
        }
    }
    Pop-Location
}
