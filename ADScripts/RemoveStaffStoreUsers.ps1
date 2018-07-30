function Get-ADUsersFromCSV {
  Param($CSVFile)
  
    Import-Csv $CSVFile | Where-Object { $_.Status -eq 'Remove' } | ForEach-Object {
        $User = $_.Path.Split(' ')[0]
        Get-ADUser -Id $User | Select-Object -Expand DistinguishedName
    }
}

#Remove-ADGroupMember -Identity -Members $ADUsers -WhatIf
function Get-ADUsersNotInStaffStore {
    Param($CSVFile)

    $Group = 'GG_WSP-File02-StaffStore_Users' 
    $GroupMembers = Get-ADGroupMember -Identity $Group | Select-Object -Expand DistinguishedName
    Import-Csv $CSVFile | Where-Object { $_.Status -eq 'Remove' } | ForEach-Object {
        $User = $_.Path.Split(' ')[0]
        $ADUser = Get-ADUser -Id $User
        If ($ADUser.DistinguishedName -notin $GroupMembers ) {
            Write-Output "$User is not in $Group"
        }
    }
}
