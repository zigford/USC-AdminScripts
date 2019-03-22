Start-Transcript -Path $(Join-Path $env:temp "DriveMapping.log")

$driveMappingConfig=@()


######################################################################
#                section script configuration                        #
######################################################################

<#
   Add your internal Active Directory Domain name and custom network
   drives below
#>

$dnsDomainName= "usc.internal"


$driveMappingConfig+= [PSCUSTOMOBJECT]@{
    DriveLetter = "G"
    UNCPath= "\\usc.internal\dfs\General"
    Description="General"
}


$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "S"
    UNCPath= "\\usc.internal\dfs\Special"
    Description="Special"
}

######################################################################
#               end section script configuration                     #
######################################################################

$connected=$false
$retries=0
$maxRetries=3

Write-Output "Starting script..."
Do {

    If (Resolve-DnsName $dnsDomainName -ErrorAction SilentlyContinue){
        $connected=$true
    } else {
        $retries++
        Write-Warning ("Cannot resolve: $dnsDomainName, assuming no" +
                " connection to fileserver")
        Start-Sleep -Seconds 3
        if ($retries -eq $maxRetries){
            Throw ("Exceeded maximum numbers of retries ($maxRetries)" +
                   "to resolve dns name ($dnsDomainName)")
        }
    }

} While (-Not ($Connected))

#Map drives
$driveMappingConfig.GetEnumerator() | ForEach-Object {
    Write-Output "Mapping network drive $($PSItem.UNCPath)"
    New-PSDrive -PSProvider FileSystem -Name $PSItem.DriveLetter `
        -Root $PSItem.UNCPath -Description $PSItem.Description -Persist `
        -Scope global -ErrorAction
    $DriveObj = New-Object -ComObject Shell.Application
    $DriveObj.NameSpace("$($PSItem.DriveLetter):").Self.Name=
        $PSItem.Description

}

Stop-Transcript