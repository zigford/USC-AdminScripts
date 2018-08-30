function Get-WimInfo {
    Param($Release='1709',$Index,$Root='appdev')
    Begin{
        $Build = Get-ReleaseBuild $Release
        $Root = Switch ($Root) {
            appdev {'\\usc.internal\dfs\appdev\SCCMPackages\OperatingSystems'}
            cap {'\\wsp-configmgr01\DeploymentShare$\Captures'}
        }
        echo $Root
        if ($Index) {
            $Index="/Index:$Index"
        }
    }

    Process {
        Dism.exe /Get-Wiminfo /WimFile:"$Root\$Build" $Index
    }
}

function Get-WimIndex {
    Param([Parameter(Mandatory=$True)]$Path)
    Get-WindowsImage -ImagePath $Path | Select-Object -Expand ImageIndex
}

function Get-WimIndexVer {
    Param([Parameter(Mandatory=$True)]$Image)
    $Ver = $null
    If ($Image.SPBuild -gt $Image.SPLevel) {
        $Ver = $Image.SPBuild 
    } else {
        $Ver = $Image.SPLevel
    }
    return $Ver
}

function Get-WimIndexDesc {
    Param([Parameter(Mandatory=$True)]$Image)
    return $Image.ImageDescription
}

function Get-WimIndexName {
    Param([Parameter(Mandatory=$True)]$Image)
    return $Image.ImageName
}

function Get-ReleaseBuild {
    Param([Parameter(Mandatory=$True)]$Release,[switch]$Number)

    $Num = Switch ($Release) {
        1607 {'14393'}
        1703 {'15063'}
        1709 {'16299'}
        1803 {'17134'}
    }
    $Build = "Microsoft Windows 10 x64 $Num.wim"
    If ($Number) {
        return $Num
    } else {
        return $Build
    }
}

function Get-BuildRelease {
    Param($Build)

    Switch ($Build) {
       14393 {'1607'}
       15063 {'1703'}
       16299 {'1709'}
       17134 {'1803'}
    }
}

function Copy-WimIndex {
    <#
    .SYNOPSIS
        Copy a WIM index to another wim file and rename the index name and description according to naming standard.
    .DESCRIPTION
        Copy the latest (or specified) index from a captured WIM into the corresponding WIM file containing builds for a specific release on appdev\SCCMPackages\OptatingSystems
    .PARAMETER Release
        Specify the release to copy, IE 1709, 1803.. etc. If not specified, prompt.
    .PARAMETER Index
        Specify the specific index inside of the Capture WIM to copy to appdev. If not specified, defaults to the last index.
    .PARAMETER SourceRoot
        Root location to copy the image from. Probably do not need to specify this, default is the MDT Deployment Share Captures directory
    .PARAMETER DestRoot
        Root location to copy the image to. Probably do not need to specify this, default is the \\usc.internal\usc\appdev\SCCMPackages\OperatingSystems package directory.
    .PARAMETER Whatif
        Switch to specify you want to run this command without performing actions. The commands that are normally run will be echoed to the console.
    .EXAMPLE
        Copy-WimIndex
    .NOTES
        notes
    .LINK
        https://github.com/zigford/USC-AdminScripts/
    #>
    Param(
        [Parameter(Mandatory=$True)]$Release,
        $Index,
        $SourceRoot='\\wsp-configmgr01\DeploymentShare$\Captures',
        $DestRoot='\\usc.internal\dfs\appdev\SCCMPackages\OperatingSystems',
        [switch]$WhatIf
    )
    
    $Build = Get-ReleaseBuild $Release
    
    If ((Test-Path "$SourceRoot\$Build") -and (Test-Path "$DestRoot\$Build")) {
        If (-Not $Index) {
            $Index = Get-WimIndex -Path "$SourceRoot\$Build" | Select-Object -Last 1
        }
        $Image = Get-WindowsImage -ImagePath "$SourceRoot\$Build" -Index $Index
        $BuildVer = Get-WimIndexVer -Image $Image
        $DestName = "Microsoft Windows 10 x64 $(Get-ReleaseBuild $Release -Number) $BuildVer"
        If ($WhatIf) {

            echo Dism /Export-Image /SourceImageFile:"$SourceRoot\$Build" /SourceIndex:$Index /DestinationImageFile:"$DestRoot\$Build" /DestinationName:"$DestName"
            Update-WimIndexDesc $Release -Whatif
        } else {
            Dism /Export-Image /SourceImageFile:"$SourceRoot\$Build" /SourceIndex:$Index /DestinationImageFile:"$DestRoot\$Build" /DestinationName:"$DestName"
            Update-WimIndexDesc $Release
        }
    }
}

Function Update-WimIndexDesc {
    <#
    .SYNOPSIS
        Update a Wim Index's name and description according to it's contents
    .DESCRIPTION
        A Usefull tool/shortcut to ImageX's ability to rename an Index and it's description. Uses defaults based on USC's image naming standards and WIM file locations.
    .PARAMETER Release
        Specify the release to work on, if not specified prompt.
    .PARAMETER Index
        Specify the index to work on, by default the last in a WIM file.
    .PARAMETER Root
        Specify the root location of the wim file. By default appdev, could also be 'cap' which is a short name for the MDT Deployment Share capture location.
    .PARAMETER Whatif
        Switch to specify that you want to run the command without performing any actions. If specified will echo the ImageX commands being run out to the console 
    .EXAMPLE
        Example
    .NOTES
        notes
    .LINK
        online help
    #>
    Param(
        [Parameter(Mandatory=$True)]$Release,
        $Index,
        $Root='appdev',
        [switch]$Whatif
    )

    $Root = Switch ($Root) {
        appdev {'\\usc.internal\dfs\appdev\SCCMPackages\OperatingSystems'}
        cap    {'\\wsp-configmgr01\DeploymentShare$\Captures'            }
    }

    $Build = Get-ReleaseBuild $Release
    $Path = "$Root\$Build"
    If (-Not $Index) {
        $Index = Get-WimIndex -Path "$Path" | Select-Object -Last 1
    }
    $Image = Get-WindowsImage -ImagePath $Path -Index $Index
    $ImageX = Find-Imagex
    #$Name = Get-WimIndexName -Image $Image
    $BuildVer = Get-WimIndexVer -Image $Image
    $Name = "Microsoft Windows 10 x64 $(Get-ReleaseBuild $Release -Number) $BuildVer"
    $CurrDesc = Get-WimIndexDesc -Image $Image
    $CmdArgs = "/INFO ""$Path"" $Index ""$Name"" ""$Release"""
    If ($Whatif) {
        Echo "Updating description from $CurrDesc to $Release"
        echo "ImageX $CmdArgs"
    } else {
        Start-Process $ImageX -argumentlist $CmdArgs -Wait -NoNewWindow
    }
}

function Find-Imagex {
    "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\imagex.exe"
}

function Copy-AllWimImages {
    <#
    .SYNOPSIS
        Update all wim images in the Appdev store with wim image indexes from the MDT Deployment Share store if their patch level is greater.
    .DESCRIPTION
        For each wim file in the capture store, read the information in the last index, if it finds that the patch level is higher than the corresponding wim+index in the appdev store, copy the index into the wim file on appdev.
    .EXAMPLE
        Copy-AllWimImages

        Deployment Image Servicing and Management tool
        Version: 10.0.14393.0

        Exporting image
        [========                   15.0%                          ]
    .NOTES
        notes
    .LINK
        online help
    #>
    $Images = Get-ChildItem -Path (cap -show) | ? PSIsContainer -eq $False
    ForEach ($ImageFile in $Images) {
        $Build = $ImageFile.BaseName -split ' ' | select -last 1
        $Release = Get-BuildRelease $Build
        $Index = Get-WimIndex -Path $ImageFile.FullName | Select-Object -Last 1
        $Image= Get-WindowsImage -ImagePath $ImageFile.FullName -Index $Index
        $CapVersion = Get-WimIndexVer -Image $Image
        $AppdevImageFile = "$(wim -show)\$($ImageFile.Name)"
        $AppdevIndex = Get-WimIndex -Path "$AppdevImageFile" | Select-Object -Last 1
        $AppdevImage = Get-WindowsImage -ImagePath "$AppdevImageFile" -Index $AppdevIndex
        $AppdevVersion = Get-WimIndexVer -Image $AppdevImage
        If ($CapVersion -gt $AppdevVersion) {
            Copy-WimIndex -Release $Release 
        }

    }

}

Function Extract-WimIndex {
    <#
    .SYNOPSIS
        Extract a single WIM Index out of a larger wim of indexes for use in a Configuration Manager Task Sequence.
    .DESCRIPTION
        USC Stores many WIM indexes in a single WIM. When it comes time to deploy a WIM through Configuration Manager, it is best to extract that WIM into a Configuration Manager package for deployment. This command is simply a shortcut for Dism /Export-Image using defaults for the USC environment.
    .PARAMETER Release
        Specify the specific release you want to extract from. Defaults to 1709 if not specified.
    .PARAMETER Index
        Specify a specific index you want to extract. Defaults to the last index of a file if not specified.
    .PARAMETER SourceRoot
        Root location to copy the image from. Probably do not need to specify this, default is to use the Appdev\SCCMPackages\OperatingSystems package directory.
    .PARAMETER DestRoot
        Root location to copy the image to. Probably do not need to specify this, default is the \\usc.internal\usc\appdev\SCCMPackages\OperatingSystems package directory.
    .EXAMPLE
        Extract-WimIndex -Release 1607

        Deployment Image Servicing and Management tool
        Version: 10.0.14393.0

        Exporting image
        [                           1.0%                           ]
    .NOTES
        notes
    .LINK
        online help
    #>
    [CmdLetBinding()]
    Param(
            [Parameter(Mandatory=$True)]$Release,
            $Index,
            $SourceRoot = (wim -show),
            $DestRoot = (wim -show),
            [switch]$Whatif
        )

    $Build = Get-ReleaseBuild $Release
    If (-Not $Index) {
        $Index = Get-WimIndex -Path "$SourceRoot\$Build" | Select-Object -Last 1
    }
    $Image = Get-WindowsImage -ImagePath "$SourceRoot\$Build" -Index $Index
    $WimName = Get-ExtractedWimName -Image $Image

    If (Test-Path -Path "$SourceRoot\$Build") {
        # Source Image exists
        Write-Verbose "Found source image $SourceRoot\$Build"
        If (Test-Path -Path "$DestRoot\$WimName" ){
            Write-Error "Wim file already found"; return
        } else {
            $CmdArgs = "/Export-Image /SourceImageFile:""$SourceRoot\$Build"" /SourceIndex:$Index /DestinationImageFile:""$DestRoot\$WimName"""
            If ($Whatif) {
                echo "Running dism with $CmdArgs"
            } else {
                Start-Process Dism -argumentlist $CmdArgs -Wait -NoNewWindow
            }
        }
    }

}

function cap{
    Param([switch]$Show)
    $Loc = '\\wsp-configmgr01\DeploymentShare$\Captures'
    if ($Show) {
        $Loc
    } else {
        sl $Loc
    }
}

function wim{
    Param([switch]$Show)
    $Loc = '\\usc\dfs\appdev\sccmpackages\Operatingsystems'
    if ($Show) {
        $Loc
    } else {
        sl $Loc
    }
}

Function Get-ExtractedWimName {
    Param([Parameter(Mandatory=$True)]$Image)
    $ImageName = $Image.ImageName
    $Release = $Image.ImageDescription
    $Build = ($Image.Version -split '\.')[2]
    Write-Verbose "Wim name is $ImageName replacing $Build for $Release"
    $ExtractedWimName = $ImageName.replace($Build,$Release)

    return "$ExtractedWimName.wim"
}
