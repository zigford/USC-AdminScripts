function New-AppLocationsCSV {

    $SiteCode = "SC1" # Site code 
    $ProviderMachineName = "wsp-configmgr01.usc.internal" # SMS Provider machine name
    $initParams = @{}
    if((Get-Module ConfigurationManager) -eq $null) {
        Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
    }
    if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
    }
    Set-Location "$($SiteCode):\" @initParams

    Write-Progress -Activity "Getting location data for all apps" -Status "Getting app list" -PercentComplete 0
    $AppList = Get-CMApplication
    Write-Progress -Activity "Getting location data for all apps" -Status "Getting package list" -PercentComplete 0
    $Packages = Get-CMPackage
    $Count = $Packages.Count +$AppList.Count
    $i=0
    $AllApps = ForEach ($App in $AppList) {
        $i=$i+1
        $Name = $App.LocalizedDisplayName
        Write-Progress -Activity "Getting location data for all apps" -Status "Reading data for: $Name" -PercentComplete ($i/$Count*100)
        If (!$App.SDMPackageXML) {
            $WMIApp = Get-WMIObject -ComputerName $ProviderMachineName -Namespace root\sms\site_$SiteCode -Query "Select * from SMS_ConfigurationItemBaseClass Where LocalizedDisplayName = '$Name'"
            $LazyPropertyLoaded = [wmi]$WMIApp.__PATH
            [xml]$XML = $LazyPropertyLoaded.SDMPackageXML
        } else {
            [xml]$XML = $App.SDMPackageXML
        }
        $XML.AppMgmtDigest.DeploymentType | ?{$_.Technology -notmatch 'DeepLink'}|%{
            $DT = $_
            $DT.Installer.Contents.Content | %{
                $Content = $_
                [PSCustomObject]@{
                    'Name'="$Name - $($DT.Title.'#text')"
                    'Type'='Application'
                    'Location'= $Content.Location
                }
            }
        }
    }

    $AllApps += $Packages | %{
        $i=$i+1
        $Name = "$($_.Manufacturer) $($_.Name)"
        Write-Progress -Activity "Getting location data for all apps" -Status "Reading data for: $Name" -PercentComplete ($i/$Count*100)
        [PSCustomObject]@{
            'Name' = $Name
            'Type' = "Package"
            'Location' = $_.PkgSourcePath
        }
    }

    Write-Progress -Activity "Getting location data for all apps" -Status "Finished" -Completed

    Set-Location C:
    $AllApps | Export-CSV allapps.csv -NoTypeInformation
}

Function Get-PackageDirs {
    $t='SCCMPackages','APPV5Packages',
    'EXE',
    'MSI',
    'Scripts',
    'BiosPackages',
    'OfficeSource'
    $r="\\usc.internal\usc\appdev"
    $i=0
    $t | %{
        If ($i -eq 0) {
            $p=gci "$r\SCCMPackages" -Directory
        } else {
            $p=gci "$r\SCCMPackages\$_" -Directory
        };
        $i=$i+1
        $p = $p.FullName -replace '.*appdev\\',''
        $p
    } | Sort-Object
}

function Compare-PackagesWithApps {
Param($CSVFile="C:\Users\adminjpharris\Documents\allapps.csv")

    $AppLocations = Import-csv $CSVFile | %{
        ($_.Location -replace '.*appdev\\','').Trim('\')
    } | Sort-Object

    Get-PackageDirs | ?{$_ -notin $AppLocations}

}

function Compare-AppsWithPackages {
Param($CSVFile="C:\Users\adminjpharris\Documents\allapps.csv")

    $Packages = Get-PackageDirs
    $Excluded = 'OSBuildUtilities'
    Import-csv $CSVFile | %{
        $Location = ($_.Location -replace '.*appdev\\','').Trim('\') 

        If ($Location -notin $Packages) {
            #Write-Verbose "$Location not found in packagedirs" -Verbose
            $Ma=$False
            $Excluded | %{
                If ($Location -match $_.Replace('\\','\\')) {
                    $Ma=$True
                }
            }
            If ($Ma -eq $False) {
                $_
            }
        }
    } | Sort-Object Name| fl

}

#Compare-PackagesWithApps
Compare-AppsWithPackages