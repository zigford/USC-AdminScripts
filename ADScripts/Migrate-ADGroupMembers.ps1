function Migrate-ADGroupMembers {
<#
    .SYNOPSIS
    Moves or copies members from one AD group into another AD group.

    .DESCRIPTION
    Foreach member of a group by default will add that member to the destination group and remove from the source group.

    .PARAMETER Source
    The Source group which is queried for members. By default, Members are removed from the group if the addition to the Destination group is successfull

    .PARAMETER Destination
    The Destination group where source group members are added to.

    .PARAMETER Copy
    If this switch is specified, members are not removed from the source group after addition to the destination group.

    .PARAMETER Confirm

    By default, a whatif action is taken on Active Directory. When mass managing Active Directory, it is recommended that a WhatIf command is run prior to ensure the desired action is taken. If you specify the Confirm parameter, all commands are final.

    .EXAMPLE
    C:\PS> Migrate-ADGroupMembers -Source "SCCM Mozilla Firefox 18.0 APPV USR" -Destination "SCCM Test App"
    Moving NWoulfe1 to SCCM Test App
    What if: Performing operation "Set" on Target "CN=SCCM Test App,OU=SCCM Targeting,OU=Utility,DC=usc,DC=internal".
    Moving PBurton to SCCM Test App
    What if: Performing operation "Set" on Target "CN=SCCM Test App,OU=SCCM Targeting,OU=Utility,DC=usc,DC=internal".

        .EXAMPLE
        C:\PS> Migrate-ADGroupMembers -Source "SCCM Mozilla Firefox 18.0 APPV USR" -Destination "SCCM Test App" -Copy -Confirm
        Copying NWoulfe1 to SCCM Test App
    Copying PBurton to SCCM Test App
    Copying PHinton to SCCM Test App
    Copying PKillen to SCCM Test App
    Copying PTaylor1 to SCCM Test App
    Copying RCarter to SCCM Test App

    .NOTES
    Author: Jesse Harris
    For: University of Sunshine Coast
    Date Created: 05 Feb 2013
    ChangeLog:
    1.0 - First Release
#>
    Param([Parameter(Mandatory=$true)]$Source,[Parameter(Mandatory=$true)]$Destination,
        [switch]$Copy,[Switch]$Confirm)

    If (-Not($Confirm)) { $WhatIfPreference = $true } Else { $WhatIfPreference = $false; $ConfirmPreference = $false; }
    $SourceGroup = Get-ADGroup -Identity $Source
    $DestinationGroup = Get-ADGroup -Identity $Destination
    #Getting Members
    $SourceMembers = Get-ADGroupMember -Identity $SourceGroup
    foreach ($Member in $SourceMembers) {
        If ($Copy) {
            Write-Host -ForegroundColor Yellow "Copying $($Member.Name) to $Destination"
            Add-ADGroupMember -Identity $DestinationGroup -Members $Member
        } Else {
            Write-Host -ForegroundColor Yellow "Moving $($Member.Name) to $Destination"
            Add-ADGroupMember -Identity $DestinationGroup -Members $Member
            If (-Not($Confirm)) {
                Remove-ADGroupMember -Identity $SourceGroup -Members $Member
            } Else {
                Remove-ADGroupMember -Identity $SourceGroup -Members $Member -Confirm:$False
            }
        }
    }
}
