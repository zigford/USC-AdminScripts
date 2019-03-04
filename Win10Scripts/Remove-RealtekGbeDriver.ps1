<#
.SYNOPSIS
    Completely remove Realtek Gbe USB Network device and driver
.DESCRIPTION
    Seems to be an issue with the 10.28.1002.2018 version of the
    Realtek Gigabit Ethernet driver for WD15 USB-Type C Docks.
    Removing this driver + device and allowing the OS to install
    the inbox version of the driver is a workaround for the issue
.PARAMETER Force
    Perform the removal without prompting
.EXAMPLE
    Remove-RealtekGbeDriver.ps1 -Force

    WARNING: Device removed, restart to enable the device with
    inbox drivers
.NOTES
    This tool requires devcon.exe. If it isn't found it will be
    downloaded from microsoft.com
.LINK
    online help
#>
[CmdLetBinding(SupportsShouldProcess)]
Param()
# Get all drivers

function Get-Driver {
    Param(
            [ValidateSet(
                "Network",
                "Audio",
                "USB",
                "HID",
                "Bluetooth",
                "Graphics"
                )]$Class
         )
    pnputil.exe /enum-drivers | ForEach-Object {
        If ($_ -match '^(?<name>\w+\s(Name|GUID|Version)):\s+(?<value>.*)$') {
            $Object | Add-Member -MemberType NoteProperty -Name $Matches.name.Replace(' ','') -Value $Matches.value
        } else {
            If ($Object) {
                If (!$Class) {
                    $Object
                } else {
                    $m = Switch ($Class) {
                        Network {"Network"}
                        Audio {"Sound"}
                        USB {"Universal Serial Bus"}
                        HID {"Human Interface Device"}
                        Bluetooth {"Bluetooth"}
                        Graphics {"Display"}
                    }
                    $Object | Where-Object {$_.ClassName -match $m}
                }
            }
            $Object = New-Object -TypeName PSCustomObject
        }
    }
}

function Remove-Driver {
    [CmdLetBinding(SupportsShouldProcess,ConfirmImpact='High')]
    Param(
        [Parameter(ValueFromPipelineByPropertyName=$True)]$PublishedName,
        [switch]$Force
    )

    Process {

        If ($PSCmdlet.ShouldProcess($PublishedName,"Remove driver")){
            If ($Force) {
                pnputil.exe /delete-driver $PublishedName /force
            } else {
                pnputil.exe /delete-driver $PublishedName
            }
        }
    }

}

function Get-Device {
    [CmdLetBinding()]
    Param([Parameter(Mandatory=$True)]$DeviceName)
    # requires devcon.exe in the path or locally

    devcon hwids * | Select-String -Pattern $DeviceName -Context 1,5 | ForEach-Object {
        $Pat = $_
        If ($Pat) {
            [PSCustomObject]@{
                "Name" = $Pat.Line -replace '^\s*Name:\s(.*)','$1'
                "HardwareID" = $Pat.Context.PostContext |
                Where-Object { $_ -notmatch 'IDs:'}|
                ForEach-Object {$_.Trim()} | Select-Object -First 1

            }
        }
    }
}

function Remove-Device {
    [CmdLetBinding(SupportsShouldProcess,ConfirmImpact='High')]
    Param(
        [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$True)]$HardwareID
    )

    If ($PSCmdlet.ShouldProcess($HardwareID,"Remove device")) {
        devcon remove "$HardwareID"
    }
}

function Test-Elevation {
   ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

function Install-Devcon {
    If (Test-Path $env:WinDir\devcon.exe) { return }
    $TempDir = New-Item -ItemType Directory -Path $ENV:Temp -Name (Get-Random)
    Push-Location
    Set-Location $TempDir
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri 'https://download.microsoft.com/download/B/5/8/B58D625D-17D6-47A8-B3D3-668670B6D1EB/wdk/Installers/787bee96dbd26371076b37b13c405890.cab' `
        -OutFile temp.cab
    New-Item -ItemType Directory -Name files
    expand.exe temp.cab -F:* files
    Move-Item files\filbad6e2cce5ebc45a401e19c613d0a28f $Env:WinDir\
    Pop-Location
    Remove-Item -Recurse -Force $TempDir
}

If (!(Test-Elevation)) {
    Start-Process -FilePath powershell.exe -Verb runAs -ArgumentList "-File $PSCommandPath"
} else {
    Install-Devcon
    Get-Device "Realtek Gbe USB" | Remove-Device
    Get-Driver -Class Network | Where-Object {
        $_.DriverVersion -match '10.28.1002.2018' -and
        $_.ProviderName -eq 'Realtek'
    } | Remove-Driver
}
