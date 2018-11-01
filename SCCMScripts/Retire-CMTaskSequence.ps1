[CmdLetBinding()]
Param($TaskSequenceName,
      [Switch]$Whatif)

# Site configuration
$SiteCode = "SC1" # Site code 
$ProviderMachineName = "wsp-configmgr01.usc.internal" 

Function InsModule {
    Param($ModuleName)
    Switch ($ModuleName) {
        'ConfigurationManager' {
            if((Get-Module ConfigurationManager) -eq $null) {
                Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
            }
        }
        Default {
            if((Get-Module $ModuleName) -eq $null) {
                If (-Not (Get-Module -ListAvailable $ModuleName -ErrorAction Continue)) {
                    Install-Module $ModuleName -Scope CurrentUser -Force
                    Import-MOdule $ModuleName
                }
            
            }
        }
    }
}

$RequiredModules = 'ConfigurationManager',
    'USC-SCCM'

$RequiredModules | ForEach-Object {
    InsModule $PSItem
}

Connect-CfgSiteServer

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}
Push-Location

Set-Location "$($SiteCode):\"
if (-Not $TaskSequenceName) {
    $TaskSequencesInDev = Get-CfgItemsByFolder -ItemType TaskSequence -FolderName Development 
    $TSs = $TaskSequencesInDev | ForEach-Object { 
        Get-CMTaskSequence -TaskSequencePackageId $PSItem.ObjectID
    }
    $i = 0
    $pos = $TSs | ForEach-Object {
        [PSCustomObject]@{
            'Index' = $i
            'TaskSequence' = $PSItem.Name
        }
        $i++
    }
    $quit = [PSCustomObject]@{'Index' = $i; 'TaskSequence' = 'QUIT '}
    If ($pos -is [System.Array]) { $pos += $quit } else { $pos = @($pos, $quit) }
    $TSSel = -1
    While ($TSSel -lt 0 -or $TSSel -gt $i) {
        $pos | Format-Table -AutoSize
        $TSSel = Read-Host -Prompt "Please chose a task sequence to retire or $i to quit)"
        If ($TSSel -eq $i) { return }
    }
    $TaskSequence = $TSs[$i]
    $TaskSequenceName = $TaskSequence.Name
} else {
    $TaskSequence = Get-CMTaskSequence -Name $TaskSequenceName
}

$TaskSequence | Set-CMTaskSequence -EnableTaskSequence $False
Move-CMObject -ObjectID $TaskSequence.PackageID -FolderPath "$SiteCode:\TaskSequence\Retired"

Pop-Location
