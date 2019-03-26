[CmdLetBinding()]
Param($ComputerName,[switch]$All=[switch]$False)

$InterestingNodes = 'Hardware','SystemInfo','DriverPackages','Programs'
$Path = If (-Not ($ComputerName)) {
    'C:\$WINDOWS.~BT\Sources\Panther'
} else {
    "\\$($ComputerName)\c$\`$WINDOWS.~BT\Sources\Panther"
}

If (-Not (Test-Path -Path $Path)) {
    throw "Cannot locate setup logs"
}

$LogFiles = Get-ChildItem -Path $Path -Filter 'CompatData*.xml'
If ($LogFiles.Count -eq 0) {
    Write-Verbose "No log files found"
    return
}

Function Get-JHBlockMap {
Param($MSBlockType)
    Switch ($MSBlockType) {
        {$_ -eq $False} {'NoBlock'}
        {$_ -eq $True}  {'ProllyNoBlock'}
        {$_ -eq 'None'} {'NoBlock'}
        {$_ -eq 'Hard'} {'Block'}
    }
}

$LogFiles | ForEach-Object {
    $report = ([xml](Get-Content $_.FullName)).CompatReport

    $report.ChildNodes.Name |
    Where-Object { $_ -in $InterestingNodes }| ForEach-Object {
        $CurrentType = $_
        $report."$_".ChildNodes | ForEach-Object {
            $BlockType =
            If ($CurrentType -eq 'DriverPackages') {
                $_.BlockMigration
            } else {
                $_.CompatibilityInfo.BlockingType
            }
            $JHBlockType = Get-JHBlockMap $BlockType
            [PSCustomObject]@{
                #'Type' = $_.Name
                'Name' = $_.Attributes."#text" | Select-Object -First 1
                'MSBlockType' = $BlockType
                'JSBlockType' = $JHBlockType
            }
        }
    }

}
