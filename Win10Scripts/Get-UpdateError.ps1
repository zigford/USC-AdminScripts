<#
.SYNOPSIS
    Scan a setupact.log and provide a human readable reason for upgrade error.
.DESCRIPTION
    Connect to a PC and find the setupact.log file, read the last $Tail lines of the log for a Win32 or NTStatus code and provide a sane human understandable message.
.PARAMETER ComputerName
    Specify the computer to attempt connection to, otherwise scan local PC.
.PARAMETER Tail
    Specify how many of the last lines of the setupact.log file to scan. Default is 10, as the error is usaully found there.
.PARAMETER SMSTS
    If the upgrade occured via a Task Sequence, attempt to read the last smsts log file for the error. Particularly usefull if the setupact.log file has been cleaned up.
.EXAMPLE
    .\Get-UpdateError -ComputerName 7ts0v72

    ComputerName : 7ts0v72
    Time         : 15/05/2018 5:04:52 AM
    Level        : Error
    Component    : MOUPG
    Error        : The operation was canceled by the user
    Detail       : Increase allowed runtime in SCCM

.NOTES
    Author: Jesse Harris
.LINK
    https://github.com/zigford/USC-AdminScripts
#>
[CmdLetBinding()]
Param(
    $ComputerName,
    [switch]$SMSTS,
    [int]$Tail = 10
    )

function Get-BlockingApp {
    [CmdLetBinding()]
    Param($Panther)

    $AppXMLs = Get-ChildItem -Path "$Panther\*_APPRAISER_SetupOutput.xml"
    If ($AppXMLs) {
        ForEach ($XmlFile in $AppXMLs) {
            $XML = [xml](Get-Content -Path $XmlFile -Raw)
            If ($XML.CompatReport.Programs.Program.CompatibilityInfo.BlockingType -eq 'Hard'){
                $XML.CompatReport.Programs.Program.Name
            }
        }
    } Else {
        "Detail not recorded as App Compat XML's don't exist. Rerun setup"
    }
}

function Get-DiskInfo {
    [CmdLetBinding()]
    Param($ComputerName)
    If ($ComputerName) {
        $Disks = Get-WmiObject -ComputerName $ComputerName -Class Win32_LogicalDisk space Root\Cimv2 | Where-Object {$_.DriveType -eq 3}
    } else {
        $Disks = Get-WmiObject -Class Win32_LogicalDisk space Root\Cimv2 | Where-Object {$_.DriveType -eq 3}
    }
    $CDriveFreeSpace = "$([int](($Disks | Where-Object {$_.DeviceID -eq 'C:'}).FreeSpace/1gb)) Gb"
    $Disks | Where-Object {$_.DeviceID -eq 'D:' -and $_.VolumeName -eq 'Scratch'} | ForEach-Object {
        If ($ComputerName) {
            $DCount = (Get-ChildItem -Path "\\$ComputerName\d$").Count
        } else {
            $DCount = (Get-ChildItem -Path D:\).Count
        }
    }
    if ($DCount) {
        $Report = "C: $CDriveFreeSpace free, $DCount files on scratch"
    } else {
        $Report = "C: $CDriveFreeSpace free"
    }
    $Report
}

function Convert-ErrorCode {
    [CmdLetBinding()]
    Param($HexCode)

        Switch ($HexCode){
            '0xC1900208' {[PSCustomObject]@{'Name'="Application Compatibility";'Detail'= Get-BlockingApp $Panther}}
            '0xC190020E' {[PSCustomObject]@{'Name'="Not enough disk space";'Detail' = Get-DiskInfo $ComputerName }}
            '0xC1900200' {[PSCustomObject]@{'Name'="Does not meet minimum requirements";'Detail'='TBA'}}
            '0x80070021' {[PSCustomObject]@{'Name'="Cannot read WIM file";'Detail'='Try TS Again'}}
            '0x800704C7' {[PSCustomObject]@{'Name'="The operation was canceled by the user";'Detail'='Increase allowed runtime in SCCM'}}
        }
}

If ($ComputerName) {
    If ((Test-Connection -ComputerName $ComputerName -Count 1 -Quiet) -eq $False `
        -and (Test-Path -Path "$ComputerName\c$") -eq $False) {
            #Write-Error 'Unable to establish connection to computer' 
            return
    }
    $RootPath = "\\$ComputerName\c$"
} else {
    $RootPath = "C:"
}

$Panther = "$RootPath\`$WINDOWS.~BT\Sources\Panther"
$SetupAct = "$Panther\setupact.log"
If ((Test-Path -Path $SetupAct) -and (-Not $SMSTS)) {
    Write-Verbose "Reading Setupact.log"
    $Last10Lines = Get-Content -Path $SetupAct -Tail 50
    $Last10Lines | ForEach-Object {
        $HexError = ([regex]'.*Result\s=\s(?<code>0[xX][0-9a-fA-F]+).*').Matches($_)
        If ($HexError | Select-Object Groups) {
            $ECode = $HexError.Groups[1].Value
            Write-Verbose "Detected Error Code: $ECode"
            $ErrorInfo = Convert-ErrorCode $ECode
            $ETrans = $ErrorInfo.Name
            $Detail = $ErrorInfo.Detail
        } else {
            $ECode = $null
            $ETrans = $null
            $Detail = $null
        }
        Try {
            $Time = [datetime]::ParseExact($_.Split(',')[0], 'yyyy-MM-dd HH:mm:ss',[System.Globalization.CultureInfo]::InvariantCulture)
        } catch {
            $Time = $null
            Write-Debug "Unable to convert $($_.Split(','[0])) to time"
        }
        [PSCustomObject]@{
            'ComputerName' = If ($ComputerName) { $ComputerName} else {$env:COMPUTERNAME}
            'Time' = $Time
            'Level' = ([regex]'.*,\s(?<error>\w+)\s+.*').Match($_).Groups[1].Value
            'Component' = ([regex]'.*,\s\w+\s+(?<comp>\w+)\s.*').Match($_).Groups[1].Value
            'Error' = $ETrans
            'Detail' = $Detail
        } | Where-Object {$_.Error -ne $Null}
    }
} else {
    # Main setuplog doesn't exist. try for an smstslog
    $SMSTSLogs = Get-ChildItem -Path "$RootPath\Windows\CCM\Logs" -Filter smsts*.log -Recurse
    ForEach ($SMSTSLog in $SMSTSLogs) {
        Get-Content -Path $SMSTSLog.FullName -Tail 100 | ForEach-Object {
            $Component = ([regex]'.*component="(?<comp>\w+)".*').Match($_).Groups[1].Value
            $Level = ([regex]'.*type="(?<type>\d)".*').Match($_).Groups[1].Value
            If ($Component -eq 'OSDUpgradeWindows' -and $Level -eq 3) {
                $time = ([regex]'.*(?<time>\d\d:\d\d:\d\d)\.\d\d\d\.*').Match($_).Groups[1].Value
                $date = ([regex]'.*date="(?<date>\d\d-\d\d-\d\d\d\d)".*').Match($_).Groups[1].Value
                If ($time -eq '' -or $date -eq '') { Write-Verbose "$_" -Verbose}
                $DateTime = [datetime]::ParseExact("$date $time", 'MM-dd-yyyy HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
                $Msg = ([regex]'<!\[LOG\[(?<msg>.*)\]LOG\]!>.*').Match($_).Groups[1].Value
                $HexError = ([regex]'.*(?<code>0[xX][0-9a-fA-F]+).*').Matches($_)
                If ($HexError | Select-Object Groups) {
                    $ECode = $HexError.Groups[1].Value
                    $ErrorInfo = Convert-ErrorCode $ECode
                    $ETrans = $ErrorInfo.Name
                    $Detail = $ErrorInfo.Detail
                } else {
                    $ECode = $null
                    $ETrans = $null
                    $Detail = $null
                }
                [PSCustomObject]@{
                    'ComputerName' = $ComputerName
                    'Time' = $DateTime
                    'Level' = $Level
                    'Component' = $Component
                    'Msg' = $Msg
                    'ErrorName' = $ETrans
                    'ErrorDetail' = $Detail
                } 
            }
        }
    }
}
