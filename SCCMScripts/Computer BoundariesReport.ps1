
Function SMSProvQuery {
    Param($Query)
    Get-WmiObject -ComputerName wsp-configmgr01 -Namespace root\sms\site_SC1 `
        -Query $Query
}

Function Get-BoundaryInformation {
    [CmdLetBinding()]
    Param([Switch]$NoCache)
    
    If ($NoCache -or -Not (Test-Path .\boundaryData.csv)) {

        If (Test-Path .\boundaryData.csv) { Remove-Item .\boundaryData.csv }
        $Boundaries = Get-WmiObject -Namespace "root\SMS\site_SC1" `
            -Class SMS_Boundary -ComputerName wsp-configmgr01 `
        | ForEach-Object {
            $BoundaryName = $_.DisplayName
            $BoundaryID = $_.BoundaryID
            If ($_.Value -match '-') {
                $BoundaryValue = $_.Value.Split("-")
                $IPStartRange = $BoundaryValue[0]
                $IPEndRange = $BoundaryValue[1]
            } else {
                $IPStartRange = $_.Value -replace '0$','1'
                $IPEndRange = $_.Value -replace '0$','254'
            }
            $ContentLocation = SMSProvQuery (
            "select groupid from SMS_BoundaryGroupMembers " +
            "where BoundaryID = '$BoundaryID'"
            ) | ForEach-Object {
                SMSProvQuery (
                    "select Description from SMS_BoundaryGroup " +
                    "where GroupID='$($_.GroupID)' and " +
                    "Name LIKE '%Content Location%'"
                )
            }
            $ParseStartIP = [System.Net.IPAddress]::
                Parse($IPStartRange).GetAddressBytes()
            [Array]::Reverse($ParseStartIP)
            $ParseStartIP = [System.BitConverter]::ToUInt32($ParseStartIP, 0)
            $ParseEndIP = [System.Net.IPAddress]::
                Parse($IPEndRange).GetAddressBytes()
            [Array]::Reverse($ParseEndIP)
            $ParseEndIP = [System.BitConverter]::ToUInt32($ParseEndIP, 0)
            [PSCustomObject]@{
                'StartIP'=$ParseStartIP;
                'EndIP'=$ParseEndIP;
                'Name'=$BoundaryName;
                'LOCALDP'=$ContentLocation.Description
            }
        }
        Write-Verbose "Writing boundary data cache"
        $Boundaries | Export-Csv .\boundaryData.csv -NoTypeInformation -Append
        $Boundaries

    } Else {

        Import-csv .\boundaryData.csv

    }
}


Function Get-IPSite {
    <#
    .SYNOPSIS
        Convert and IP Address to a site name based on Boundary groups
    .DESCRIPTION
        Given an ip address and a boundary group list, find which boundary
        the IP address resides in and output the name of the boundary group
    .PARAMETER IPAddress
        Specify the string that is the IP address
    .EXAMPLE
        Example
    .NOTES
        notes
    .LINK
        online help
    #>
    [CmdLetBinding()]
    Param(
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$True)]
            $IPAddress
         )
    Begin
    {
       $Boundaries = Get-BoundaryInformation 
    }

    Process 
    {

        Try {

        $ParseIP = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
        [Array]::Reverse($ParseIP)
        $ParseIP = [System.BitConverter]::ToUInt32($ParseIP, 0)
        } catch {
        Write-Warning "Could not parse $IPAddress"
        return
        }

        $BoundaryInfo = $Boundaries | Where-Object {
            ($_.StartIP -le $ParseIP) -and ($ParseIP -le $_.EndIP)
        } | Select-Object -First 1
        $BName = $BoundaryInfo.Name
        $LDP = $BoundaryInfo.LOCALDP

        [PSCustomObject]@{
            'IP' = $IPAddress
            'BoundaryName' = $BName
            'LocalDP' = $LDP
        }
    }
}

Function Get-BestBoundaryName {
    [CmdLetBinding()]
    Param($BoundaryNames,$IPAddresses)

    If ($IPAddresses) {

        $BoundaryNames = $IPAddresses | ForEach-Object {
            (Get-IPSite $_).BoundaryName
        }

    }

    $Weighted = $BoundaryNames | ForEach-Object {
        [PSCustomObject]@{
            Name = $_;
            Weight = Switch ($_) {
                {$_ -match 'Hyper|NAT|Azure|VM'}  { 9 }
                {$_ -eq $Null}                    { 8 }
                'USC Wifi'                        { 2 }
                Default                           { 1 }
            }
        }
    }

    $Weighted | Sort-Object -Property Weight | Select-Object -First 1 -ExpandProperty Name
}

Function Get-SiteReport {
    [CmdLetBinding()]
    Param(
        $Collection="All USC Non-Volatile Computers",
        $CacheFile
    )

    If ($CacheFile -and (Test-Path $CacheFile)) {
        $Computers = Import-CSV $CacheFile 
    } else {
        Write-Verbose "Creating cache file" 
        $Computers = Get-CfgCollectionMembers $Collection |
        Get-CfgClientInventory `
            -Properties Model | ForEach-Object {
            $IPs = $_.IPAddresses | Where-Object {
                ([System.Net.IPAddress]::Parse($_)).AddressFamily -eq
                    "InterNetwork"
            }
            $_ | Select-Object ComputerName,LastLogonUserName,Model,
                @{label='Boundary';expression={
                    (Get-BestBoundaryName -IPAddresses $IPs)
                }},
                @{label='PrimaryWKSGroup';expression={
                    (Get-LabGroup $_.ComputerName).Lab
                }}
        }
        $Computers | Export-CSV CacheFile.csv
    }

    $Computers
}

Function Get-ComputerSite {
    <#
    .SYNOPSIS
        Show which site a computer belongs to
    .DESCRIPTION
        Given a computername, connect to Config Manager and get it's IP.
        Then convert that IP to a boundary/site name.
    .PARAMETER ComputerName
        Specify the string that is the ComputerName
    .EXAMPLE
        Example
    .NOTES
        notes
    .LINK
        online help
    #>
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$True)]
        $ComputerName
    )

    Begin {

       Import-Module USC-SCCM
       Connect-CfgSiteServer

    }

    Process {

        $Computer = Get-CfgClientInventory -ComputerName $_.ComputerName
        If ($Computer) {
            $IPAddress = $Computer.IPAddresses | Where-Object {
                ([System.Net.IPAddress]::Parse($_)).AddressFamily -eq
                    "InterNetwork"
            }
            If ($IPAddress) {
                ForEach ($IP in $IPAddress) {
                    $IPInfo = Get-IPSite $IP
                    [PSCustomObject]@{
                        ComputerName = $_.ComputerName
                        Site = $IPInfo.BoundaryName
                        IPAddress = $IP
                    }
                }
            }
        }
    }
}

Function Get-BestSiteMatch {
    Param($CSV=".\boo.csv")

    Import-Csv $CSV | Group-Object -Property ComputerName |? Count -ge 5
}

function Get-LabGroup {
    Param($ComputerName)
    $ADObject = Get-ADComputer -id $Computername -prop memberof
    $Members = $ADObject.MemberOf | Where-Object {
         $_ -match 'WKS_(?!(Inactive|Research_))'
    }
    [PSCustomObject]@{
        ComputerName = $Computername
        Lab = if ($Members -ne $null) {
            $RegEx = [regex]'^CN=WKS_(?<Lab>\w+),.*$'
            $RegEx.Match($Members).Groups['Lab'].Value
        } else {
            $null
        }
    }
}
