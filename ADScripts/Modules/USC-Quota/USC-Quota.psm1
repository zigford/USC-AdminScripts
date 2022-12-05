function Get-USCQuota {
<#
    .SYNOPSIS
    Retreive Quota information using dirqutoa with an FSRM Windows server.
    
    .DESCRIPTION
    Uses dirquota.exe and parses returned strings into a custom object usable in Powershell.
    
    .PARAMETER TemplateName
    The name of a quota template. Restricts query to return results from Quota's matching named template.

    .PARAMETER ListTemplates
    A switch which will simply output a list of templates configured on the FSRM server.

    .PARAMETER Server
    Accepts the name of the FSRM you are connecting to. Defaults to WSP-File02
    
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
#>
	Param($UserName,[string[]]$TemplateName,$Server="wsp-file02",[Switch]$ListTemplates)
	If (! (Test-CurrentAdminRights) ) { Write-Host -ForegroundColor Red "Please run as Admin"; return }
    If ($ListTemplates) {
    	$QuotaCMD = dirquota t l /remote:$($Server)
	    $QuotaCMD | Select-String -Pattern "Template Name" -Context 0,6 | `
            %{$NewObj = "" | Select-Object TemplateName,Limit,Type; 
                $NewObj.TemplateName = $_.Line.Split(":")[1].TrimStart(" "); 
                $NewObj.Limit = $_.Context.PostContext[0].Split(":")[1].TrimStart(" ").Split("(")[0]; 
                $NewObj.Type = $_.Context.PostContext[0].Split("(")[1].Split(")")[0];
                $NewObj}
    } Else {
        
        $defaultProperties = @('UserName','Available', 'Used')
        $defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet',[string[]]$defaultProperties)
        $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)
        If ( $TemplateName -ne $null ) {$SourceTemplate = "/sourcetemplate:$($TemplateName)"}
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
                $QuotaPath = "/path:j:\staffhome\$($User.SamAccountName)"
            } ElseIf ( $User.DistinguishedName -match "Student" ) {
                $QuotaPath = "/path:f:\studenthome\$($User.SamAccountName)"
            } Else { Write-Host -ForegroundColor Red "$Username folder not found"; return }
        }
        
        $ErrorActionPreference = "SilentlyContinue"
        dirquota.exe q l /remote:$($Server) $SourceTemplate $QuotaPath | Select-String -Pattern "Quota Path" -Context 0,12 |
            %{
                $Line = 0
                While ( ($_.Context.PostContext[$Line] -match "\\") ) { $Line++ }
                New-Object -TypeName PSObject -Property @{
                    'UserName' = $_.Line.Split("\") | Select-Object -Last 1;
                    'Path' = $_.Line.Split(":",2)[1].TrimStart(" ");
                    'SharePath' = $_.Context.PostContext[0].Split(":")[1].TrimStart(" ");
                    'TemplateName' = $_.Context.PostContext[$Line].Split(":")[1].TrimStart(" ");
                    'Status' = $_.Context.PostContext[$Line+1].Split(":")[1].TrimStart(" ");
                    'Used' = $_.Context.PostContext[$Line+3].Split(":")[1].TrimStart(" ").Split("(")[0];
                    'PercentUsed' = [int]$_.Context.PostContext[$Line+3].Split("(")[1].Split("%")[0];
                    'Available' = $_.Context.PostContext[$Line+4].Split(":")[1].TrimStart(" ");
                    'Peak' = $_.Context.PostContext[$Line+5].Split(":")[1].TrimStart(" ").Split("(")[0];
                } | Add-Member MemberSet PSStandardMembers $PSStandardMembers -PassThru
            }
    }
            $ErrorActionPreference = "Continue"
}

function Set-USCQuota {
<#
    .SYNOPSIS
    Sets a quota template on a path using dirqutoa.exe with an FSRM Windows server.
    
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
    Param([Parameter(Mandatory = $true,
                     ValueFromPipeLine = $true,
                     ValueFromPipeLineByPropertyName = $false)]$Path,$TemplateName="2.5GB Hard Limit",$server="wsp-file02")
	BEGIN {
        If (! (Test-CurrentAdminRights) ) { Write-Host -ForegroundColor Red "Please run as Admin"; return }
    }

    PROCESS {

    function Set-USCQuotaWorker {
        Param($Path,$TemplateName)    
            $QuotaCMD = dirquota q m /remote:$($Server) /Path:$Path /sourcetemplate:$TemplateName
            If ( $QuotaCMD -match "successfully" ) { Write-Host "Quota path $Path modified to $TemplateName successfully" }
            Else { Write-Host $QuotaCMD }
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
}

function Test-CurrentAdminRights {
    #Return $True if process has admin rights, otherwise $False
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Role = [System.Security.Principal.WindowsBuiltinRole]::Administrator
    return (New-Object Security.Principal.WindowsPrincipal $User).IsInRole($Role)
 }

function Invoke-AsAdmin() {
    Param([System.String]$ArgumentString = "")
    $NewProcessInfo = new-object "Diagnostics.ProcessStartInfo"
    $NewProcessInfo.FileName = [System.Diagnostics.Process]::GetCurrentProcess().path
    $NewProcessInfo.Arguments = "-file " + $MyInvocation.MyCommand.Definition + " $ArgumentString"
    $NewProcessInfo.Verb = "runas"
    $NewProcess = [Diagnostics.Process]::Start($NewProcessInfo)
    $NewProcess.WaitForExit()
}