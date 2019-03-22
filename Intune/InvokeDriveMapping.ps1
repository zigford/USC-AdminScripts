$repo = "https://raw.githubusercontent.com/zigford/USC-AdminScripts"
$MappingScriptUrl = "${repo}/master/Intune/DriveMappingScript.ps1"
$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

$Pwsh = 'PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -command '
$Pwsh += "$([char]34)& {
    `$Script = Invoke-RestMethod '$MappingScriptUrl'
    `$Script = `$Script.Replace('ï','').Replace('»','').Replace('¿','')
    `$Script | Invoke-Expression
}$([char]34)"

if (-Not (Test-Path -Path $regKey)){
    New-ItemProperty -Path $regKey -Force
}

Set-ItemProperty -Path $regKey -Name "IntuneDriveMapping" -Value $Pwsh -Force
Invoke-Expression $Pwsh