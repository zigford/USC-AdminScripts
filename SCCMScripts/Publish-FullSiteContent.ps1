<#
.SYNOPSIS
    Publish all CM site content to a local disk for setting up a prestaged DP.  
.DESCRIPTION
    Use the config manager powershell module, Get-CM<Content-Type> commandlets and Publish-CMContent to create a store of all packages/programs/operating systems/updates and boot images.
.PARAMETER Destination
    Specify the local folder to store the content.
.PARAMETER DP
    Specify the distribution point to retreive content from
.NOTES
    Author: Jesse Harris
.LINK
    online help
#>
[CmdLetBinding()]
Param($DP="WSP-CONFIGMGR01.USC.INTERNAL",$Destination='D:\')

Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" # Import the ConfigurationManager.psd1 module 
Push-Location
Set-Location "SC1:" # Set the current location to be the site code.
$i=0
Write-Progress -Activity "Getting Package Lists" -Status "Getting list of applications" -id 0 -PercentComplete 0
$Applications = Get-CMApplication -Fast | ?{$_.IsDeployed -and $_.IsLatest -and $_.HasContent}
Write-Progress -Activity "Getting Package Lists" -Status "Getting list of packages" -id 0 -PercentComplete 17
$Packages = Get-CMPackage
Write-Progress -Activity "Getting Package Lists" -Status "Getting list of driver packages" -id 0 -PercentComplete 34
$DriversPackages = Get-CMDriverPackage
Write-Progress -Activity "Getting Package Lists" -Status "Getting list of boot images" -id 0 -PercentComplete 50
$BootImages = Get-CMBootImage
Write-Progress -Activity "Getting Package Lists" -Status "Getting list of system images" -id 0 -PercentComplete 67
$OperatingSystemImagess = Get-CMOperatingSystemImage
Write-Progress -Activity "Getting Package Lists" -Status "Getting list of OS Upgrades" -id 0 -PercentComplete 84
$OperatingSystemInstaller = Get-CMOperatingSystemInstaller
Write-Progress -Activity "Getting Package Lists" -Status "Complete" -id 0 -Completed

function Publish-Content {
[CmdLetBinding()]
Param($List,$Type,$Destination='D:\',$DP = "WSP-CONFIGMGR01.USC.INTERNAL")
    $i=0
    
    
    $ContentPath = Join-Path -Path $Destination -ChildPath $Type
    If (-Not (Test-Path -Path $ContentPath)) {New-item -Path $ContentPath -ItemType Directory}
    $LogFile = "$ContentPath\Failed.log"
    Switch ($Type) {
        'Application'{
            $List | %{
                $i++
                $Name = "$($_.LocalizedDisplayName)"
                Write-Progress -Activity "Provisioning $Type" -Status "$Name`: $i of $($List.Count)" -PercentComplete (100/$List.Count*$i) -id 0
                Try {
                    If (-Not (Test-Path -Path "$ContentPath\$Name.pkgx")) {
                        Publish-CMPrestageContent -FileName "$ContentPath\$Name.pkgx" -ApplicationId $_.CI_ID -DistributionPointName $DP
                    }
                } catch {
                    Write-Output "Failed to publish $Name" |Out-File $LogFile -Append
                }
            }
        }
        'Package' {
            $List | %{
                $i++
                $Name = "$($_.Name)_$($_.Version)"
                Write-Progress -Activity "Provisioning $Type" -Status "$Name`: $i of $($List.Count)" -PercentComplete (100/$List.Count*$i) -id 0

                Try {
                    If (-Not (Test-Path -Path "$ContentPath\$Name.pkgx")) {
                        Publish-CMPrestageContent -FileName "$ContentPath\$Name.pkgx" -PackageId $_.PackageID -DistributionPointName $DP
                    }
                } Catch {
                    Write-Output "Failed to publish $Name" |Out-File $LogFile -Append
                }
            }
        }
        'DriverPackage' {
            $List | %{
                $i++
                $Name = "$($_.Name)"
                Write-Progress -Activity "Provisioning $Type" -Status "$Name`: $i of $($List.Count)" -PercentComplete (100/$List.Count*$i) -id 0
                Try {
                    If (-Not (Test-Path -Path "$ContentPath\$Name.pkgx")) {
                        Publish-CMPrestageContent -FileName "$ContentPath\$Name.pkgx" -DriverPackageId $_.PackageId -DistributionPointName $DP
                    }
                } Catch {
                    Write-Output "Failed to publish $Name" |Out-File $LogFile -Append
                }
            }
        }
        'BootImage' {
            $List | %{
                $i++
                $Name = "$($_.Name)"
                Write-Progress -Activity "Provisioning $Type" -Status "$Name`: $i of $($List.Count)" -PercentComplete (100/$List.Count*$i) -id 0
                Try {
                    If (-Not (Test-Path -Path "$ContentPath\$Name.pkgx")) {
                        Publish-CMPrestageContent -FileName "$ContentPath\$Name.pkgx" -BootImageId $_.PackageId -DistributionPointName $DP
                    }
                } Catch {
                    Write-Output "Failed to publish $Name" |Out-File $LogFile -Append
                }
            }
        }
        'OperatingSystemImage' {
            $List | %{
                $i++
                $Name = "$($_.Name)"
                Write-Progress -Activity "Provisioning $Type" -Status "$Name`: $i of $($List.Count)" -PercentComplete (100/$List.Count*$i) -id 0
                Try {
                    If (-Not (Test-Path -Path "$ContentPath\$Name.pkgx")) {
                        Publish-CMPrestageContent -FileName "$ContentPath\$Name.pkgx" -OperatingSystemImageId $_.PackageID -DistributionPointName $DP
                    }
                } Catch {
                    Write-Output "Failed to publish $Name" |Out-File $LogFile -Append
                }
            }
        }
        'OperatingSystemInstaller' {
            $List | %{
                $i++
                $Name = "$($_.Name)"
                Write-Progress -Activity "Provisioning $Type" -Status "$Name`: $i of $($List.Count)" -PercentComplete (100/$List.Count*$i) -id 0
                Try {
                    If (-Not (Test-Path -Path "$ContentPath\$Name.pkgx")) {
                        Publish-CMPrestageContent -FileName "$ContentPath\$Name.pkgx" -OperatingSystemInstallerId $_.PackageID -DistributionPointName $DP
                    }
                } Catch {
                    Write-Output "Failed to publish $Name" |Out-File $LogFile -Append
                }
            }
        }
    }

}

Publish-Content -List $Applications -Type Application
Publish-Content -List $DriversPackages -Type DriverPackage
Publish-Content -List $Packages -Type Package
Publish-Content -List $DriversPackages -Type DriverPackage
Publish-Content -List $BootImages -Type BootImage
Publish-Content -List $OperatingSystemImagess -Type OperatingSystemImage 
Publish-Content -List $OperatingSystemInstaller -Type OperatingSystemInstaller

Pop-Location