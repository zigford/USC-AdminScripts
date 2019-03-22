$repo = "https://raw.githubusercontent.com/zigford/USC-AdminScripts"
$MappingScriptUrl = "${repo}/master/Intune/DriveMappingScript.ps1"
$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

$Pwsh = 'PowerShell.exe -ExecutionPolicy Bypass -command '
$Pwsh += "$([char]34)& {(Invoke-RestMethod '$MappingScriptUrl')"
$Pwsh += ".Replace('ï','').Replace('»','').Replace('¿','')" 
$Pwsh += "|Invoke-Expression}$([char]34)"

if (-Not (Test-Path -Path $regKey)){
    New-ItemProperty -Path $regKey -Force
}

Set-ItemProperty -Path $regKey -Name "IntuneDriveMapping" -Value $Pwsh -Force
Invoke-Expression $Pwsh