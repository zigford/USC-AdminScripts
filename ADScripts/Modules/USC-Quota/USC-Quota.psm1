function Test-FSRMAccess {
    [CmdLetBinding()]

    # Check running with admin account
    $ADUserCheckParams = @{
        Filter = {name -eq ${env:username}}
        Server = 'usc.internal'
        SearchBase = "OU=Privileged Users and Groups,OU=Utility,DC=usc,DC=internal"
    }
    If (-not (Get-ADUser @ADUserCheckParams)) {
        Write-Error ("Run with admin account (usc\${env:username}1i)") -ErrorAction Stop
    }

    # Check module is available and attempt to repair
    $PS = If ($IsCoreCLR) {'PowerShell'}Else{'WindowsPowerShell'}
    $LocalModulePath = "${env:userprofile}\Documents\$PS\Modules"
    $RemoteModulePath = "\\usc.internal\usc\appdev\General\SCCMTools\Scripts\Modules\FileServerResourceManager"
    # Make sure the module is installed/can be loaded.
    If (-Not (Get-Module -ListAvailable FileServerResourceManager -EA SilentlyContinue)) {
        If (-Not (Test-Path -Path $LocalModulePath)) {
            New-Item -ItemType Directory -Path $LocalModulePath
        }
        Copy-Item -Recurse -Path $RemoteModulePath -Destination $LocalModulePath
    }
    If ($IsCoreCLR) {
        Import-Module FileServerResourceManager -SkipEditionCheck
    } Else {
        Import-Module FileServerResourceManager
    }
}

function Get-HRLimit {
    # convert bytes into human readable number
    Param($Size)
    If ($Size -gt 1099511627776) {
        return "{0:0.##} TB" -f ($Size /1024/1024/1024/1024)
    } elseif ($Size -gt 1073741824) {
        return "{0:0.##} GB" -f ($Size /1024/1024/1024)
    } elseif ($Size -gt 1048576) {
        return "{0:0.##} MB" -f ($Size /1024/1024)
    } elseif ($size -gt 1024) {
        return "{0:0.##} KB" -f ($Size /1024)
    } else {
        return "$Size B"
    }
}

function Get-USCQuota {
<#
    .SYNOPSIS
    Retreive Quota information using FileServerResourceManager PowerShell modules.
    The existance of FileServerResourceManager modules make the USC-Quota module mostly redundant,
    but hey, some people still use it.
    
    .DESCRIPTION
    Originally used dirquota.exe and parsed results out to PowerShell objects. Now that FileServerResouceManage
    module exists, this functions job is to replicate the old dirquote outputs to maintaine legacy scripts.
    
    .PARAMETER TemplateName
    The name of a quota template. Restricts query to return results from Quota's matching named template.

    .PARAMETER ListTemplates
    A switch which will simply output a list of templates configured on the FSRM server.

    .PARAMETER Server
    Accepts the name of the FSRM you are connecting to. Defaults to WSP-FILE-VS48
    
    .EXAMPLE
    C:\PS>Get-USCQuota -ListTemplates
    
    TemplateName                            Limit                                   Type
    ----                                    -----                                   ----
    100 MB Limit                            100.00 MB                               Hard
    2.5GB Auto Soft Limit                   2.50 GB                                 Soft
    5GB Limit                               5.00 GB                                 Hard
    100GB Limit                             100.00 GB                               Soft
    2.5GB Hard Limit                        2.50 GB                                 Hard
    10GB Limit                              10.00 GB                                Hard
    30GB Limit                              30.00 GB                                Hard

    .EXAMPLE    
    C:\PS>Get-USCQuota -TemplateName "10GB Limit"

    UserName                                                    Available
    --------                                                    ---------
    JTindall                                                    3.44 GB
    SSmit                                                       1.02 GB
    MKlinker                                                    3.22 GB
    mmooi                                                       4.90 GB
    rlyons                                                      2.99 GB
    
    .EXAMPLE
    C:\PS>Get-USCQuota -TemplateName "2.5GB Auto Soft Limit" | Select-Object *

    UserName    : jpharris
    Path        : J:\staffhome\jpharris
    SharePath   : \\WSP-FILE02\staffhome\jpharris
    Template    : 2.5GB Hard Limit (Matches template)
    Status      : Enabled
    Used        : 1.28 GB
    PercentUsed : 51
    Available   : 1.22 GB
    Peak        : 2.42 GB

    .EXAMPLE
    C:\PS>Get-USCQuota -UserName jpharris
    
    UserName                                                    Available
    --------                                                    ---------
    JPharris                                                    1.93 GB

    .EXAMPLE
    C:\PS>Get-USCQuota -UserName jpharris | Set-USCQuota -TemplateName "5GB Limit"
    Quota path j:\staffhome\JPharris modified to 5GB Limit successfully
    
    .NOTES
    Author: Jesse Harris
    For: University of Sunshine Coast
    Date Created: 30 March 2012        
    ChangeLog:
    1.0 - First Release
    1.1 - Changed to use the new [pscustomobject]
    1.2 - Changed to reduce lag and show data immediately
    1.3 - [14/11/16 Darryl Rees] Changed to make work with win10 dirquota (parse with regex)
    1.3.1 - [18/04/2017 DR] Changed regexes to match sizes with commas and/or ending with KB or bytes
    1.3.2 - [10/05/2017 JH] Added new parameter -Scan to update statistics prior to retreival
    2.0   - [05/12/2022 JH] Replace dirquota with native FSRM modules. You should use these modules directly.
                            These changes are more of a shim for existing use cases around this module.
#>
    [CmdLetBinding()]
	Param($UserName,[string[]]$TemplateName,$Server="wsp-file-vs48",[Switch]$ListTemplates,[switch]$Scan)
    Begin {
        # Crack open a CimSession to the Server.
        $USCCimS = New-CimSession -ComputerName $Server
        Test-FSRMAccess
    }
    Process {
        If ($ListTemplates) {
            Get-FsrmQuotaTemplate -CimSession $USCCimS |
            Select-Object @{label='TemplateName';expression={$_.Name}},
                        @{label='Limit';expression={(Get-HRLimit $_.Size)}},
                        @{label='Type';expression={If($_.SoftLimit){'Soft'}else{'Hard'}}}
        } Else {
            
            $defaultProperties = @('UserName','Available', 'Used')
            $defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet',[string[]]$defaultProperties)
            $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)
            If ( $UserName -ne $null ) {
                If (!(Get-Module -Name ActiveDirectory)) {
                    If (!(Get-Module -ListAvailable -Name ActiveDirectory)) { Write-Host -ForegroundColor Red "RSA Tools not available"; return } Else {
                        Import-Module -Name ActiveDirectory
                    }
                }
                Try {
                    $User = Get-ADUser -Identity $UserName
                } Catch { 
                    Write-Host -ForegroundColor Red "$Username not found"; return 
                }
                If ( $User.DistinguishedName -match "Staff" ) {
                    $QuotaPath = "J:\staffhome\$($User.SamAccountName)"
                } ElseIf ( $User.DistinguishedName -match "Student" ) {
                    $QuotaPath = "F:\studenthome\$($User.SamAccountName)"
                } Else { Write-Host -ForegroundColor Red "$Username folder not found"; return }
            }

            If ($Scan) {
                Write-Verbose "Scanning quota to update statistics" -Verbose
                Update-FsrmQuota -CimSession $USCCimS $QuotaPath | Out-Null
                Start-Sleep -Seconds 10
            }
            If ($TemplateName) {
                Get-FsrmQuota -CimSession $USCCimS | Where-Object {
                    $_.Template -eq $TemplateName -And
                    $_.MatchesTemplate}
            } else {
                Get-FsrmQuota -CimSession $USCCimS -Path $QuotaPath |
                Select-Object @{label='UserName';expression={$_.Path.split('\')[-1]}},
                            Path,@{label='TemplateName';expression={$_.Template}},
                            @{label='Status';expression={If($_.Disabled){'Disabled'}else{'Enabled'}}},
                            @{label='Used';expression={Get-HRLimit -Size $_.Usage}},
                            @{label='PercentUsed';expression={"{0:0}%" -f ($_.Usage/$_.Size*100) }},
                            @{label='Available';expression={Get-HRLimit -Size ($_.Size - $_.Usage)}},
                            @{label='Peak';expression={Get-HRLimit -Size $_.PeakUsage}}
            }
        }
    }
    End {
        Remove-CimSession $USCCimS
    }
}

function Set-USCQuota {
<#
    .SYNOPSIS
    Sets a quota template on a path using the FileServerResourceManager PowerShell module on an FSRM Windows server.
    
    .DESCRIPTION
    Uses dirquota.exe and output from Get-USCQuota to modify a path quota to match that of a quota Template.
    
    .PARAMETER TemplateName
    The name of a quota template. Specifies the quota template to use on a path.

    .PARAMETER Path
    Specified the folder path to modify quota on.

    .PARAMETER Server
    Accepts the name of the FSRM you are connecting to. Defaults to WSP-File02
    
    .EXAMPLE
    C:\PS>Set-USCQuota -Path "J:\Staffhome\jpharris" -TemplateName "2.5GB Hard Limit"
    
    Quota path J:\Staffhome\jpharris modified to 2.5GB Hard Limit successfully

    .EXAMPLE    
    C:\PS>Get-USCQuota -TemplateName "2.5GB Auto Soft Limit" | Where-Object { $_.PercentUsed -lt 200 } | Set-USCQuota -TemplateName "5GB Limit"

    Quota path J:\staffhome\mmcallis modified to 5GB Limit successfully
    Quota path J:\staffhome\SDauk modified to 5GB Limit successfully
    Quota path J:\staffhome\vschriev modified to 5GB Limit successfully
    Quota path J:\staffhome\NKing modified to 5GB Limit successfully
    Quota path J:\staffhome\lcameron modified to 5GB Limit successfully
    Quota path J:\staffhome\jwatson modified to 5GB Limit successfully
    Quota path J:\staffhome\tlucke modified to 5GB Limit successfully
    Quota path J:\staffhome\msiddiqu modified to 5GB Limit successfully

    .EXAMPLE
    C:\PS>Get-Contents Paths.txt | Set-USCQuota -TemplateName "100 MB Limit"

    .NOTES
    Author: Jesse Harris
    For: University of Sunshine Coast
    Date Created: 30 March 2012        
    ChangeLog:
    1.0 - First Release
#>
    [CmdletBinding(SupportsShouldProcess)]
    Param([Parameter(Mandatory = $true,
                     ValueFromPipeLine = $true,
                     ValueFromPipeLineByPropertyName = $false)]$Path,$TemplateName="2.5GB Hard Limit",$server="wsp-file-vs48")
	BEGIN {
        $USCCimS = New-CimSession -ComputerName $Server
        Test-FSRMAccess
    }

    PROCESS {

        function Set-USCQuotaWorker {
            [CmdLetBinding(SupportsShouldProcess)]
            Param($Path,$TemplateName)    
                Reset-FsrmQuota -CimSession $USCCimS -Path $Path -Template $TemplateName
                Write-Verbose "Quota path $Path modified to $TemplateName successfully"
            }
        
        #Verify Template
        $Templates = Get-USCQuota -ListTemplates
        If ( ! ($Templates | Where-Object { $_.TemplateName -eq $TemplateName }) ) { 
            Write-Host "No such template exists"
            $Templates
            return
        }
        If ( $PSBoundParameters.ContainsKey('Path') ) {

            $Path | ForEach-Object {
                If ($_ | Get-Member -Name Path) {
                    Set-USCQuotaWorker -Path $_.Path -TemplateName $TemplateName
                } Else {
                    Set-USCQuotaWorker -Path $_ -TemplateName $TemplateName
                }
            } 
        } Else {
            Set-USCQuotaWorker -UserName $UserName -TemplateName $TemplateName
        }
    }
    End{
        Remove-CimSession $USCCimS
    }
}