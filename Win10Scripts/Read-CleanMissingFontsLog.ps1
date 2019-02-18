#Quick script to show which fonts have been deleted from a machine during upgrade by parsing the CleanMissingFonts.ps1.log

Get-Content "C:\Windows\CCM\Logs\CleanMissingFonts.ps1.log" | Select-String -Pattern '^VERBOSE: Deleting Value.*from HKEY_.*$'|%{
    [regex]$reg = '^VERBOSE: Deleting Value\s(?<font>.*)\s.*from HKEY_.*$'
    $reg.Match($_).Groups[1].Value
} |%{

    Write-Verbose "Working on font $_"
    $Font = $_
    $FontFile = (Get-Item -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts').GetValue($_)
    $FontFile |%{If ($_ -eq $null){$Font}}
}

#VERBOSE: Deleting Value Arial Narrow Bold (TrueType) from HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts