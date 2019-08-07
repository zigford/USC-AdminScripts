<#
.SYNOPSIS
    Create model based collections from Driver Packages.
.DESCRIPTION
    Get all driver packages, based on the naming convention, determin
    model names from driver package and create a collection with a 
    supporting WMI query.
    This information can then be used to trim supported models
.PARAMETER SiteCode
    Specify the sitecode of your Config Manager site
.PARAMETER SiteServer
    Specify the hostname of your Config Manager provider to connect to
.EXAMPLE
    Sync-ModelCollections
.NOTES
    notes
.LINK
    online help
#>

[CmdLetBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
Param(
    [Parameter(Mandatory=$True)]$SiteCode,
    [Parameter(Mandatory=$True)]$SiteServer
)
    $SCCMOpts = @{
        SiteCode = $PSBoundParameters.SiteCode
        SiteServer = $PSBoundParameters.SiteServer

    }

# Customizations
# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer @initParams
}

function Get-DriverPackageModels {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$True)]$SiteCode,
        [Parameter(Mandatory=$True)]$SiteServer
    )
    
    Push-Location
    Set-Location "$($SiteCode):\"
    Get-CMDriverPackage | ForEach-Object { 
        if ($_.Name -match 'Win\d+x(86|64)-(?!Boot)(?<model>.*)') {
            $Matches['model']
        }
    }
    Pop-Location
}

function Select-NonExsitentialCollections {
    [CmdLetBinding() ]
    Param(
            [Parameter(
                ValueFromPipeline=$True
            )]$Collection,
            [Parameter(Mandatory=$True)]$SiteCode,
            [Parameter(Mandatory=$True)]$SiteServer
    )
    Begin {
        Push-Location
        Set-Location "$($SiteCode):\"
    }
    Process {
        if (
                (Get-CMCollection -Name $Collection) -isnot 
                [Microsoft.ConfigurationManagement.ManagementProvider.ResultObjectBase]
        )
        {
            return $Collection
        }
    }
    End{
        Pop-Location
    }
}

function Get-ModelQuery {
    Param($Model)
    return 'select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM_PRODUCT on SMS_G_System_COMPUTER_SYSTEM_PRODUCT.ResourceID = SMS_R_System.ResourceId where SMS_G_System_COMPUTER_SYSTEM_PRODUCT.Name = "' + $Model + '"'
}

function New-ModelCollection {
    [CmdLetBinding(SupportsShouldProcess) ]
    Param(
            [Parameter(
                ValueFromPipeline=$True
            )]$CollectionName,
            [Parameter(Mandatory=$True)]$SiteCode,
            [Parameter(Mandatory=$True)]$SiteServer
    )
    Begin {
        Push-Location
        Set-Location "$($SiteCode):\"
        $DailySchedule = New-CMSchedule `
            -RecurCount 1 `
            -RecurInterval Days `
            -Start (Get-Date "Friday, 25 October 2013 3:05:00 AM") `
            -DurationInterval Days `
            -DurationCount 0 `
            -Whatif:$False
    }
        
    Process {
        $CollectionOptions = @{
            CollectionType = 'Device'
            Name = $CollectionName
            LimitingCollectionName = "All USC Windows 10 Devices"
            RefreshSchedule = $DailySchedule
        }

        Write-Verbose ("Creating collection for {0}" -f $CollectionName)
        $Collection = New-CMCollection @CollectionOptions

        $CollectionRule = @{
            CollectionId = $Collection.CollectionID
            QueryExpression = (Get-ModelQuery -Model $CollectionName)
            RuleName = $CollectionName
        }
        
        $ColQuery = $Collection.CollectionRules
        If (!$ColQuery) {
            Write-Verbose ("Adding collection membership rule to {0}"  `
                -f $CollectionName)
            If ($Collection) {
                $ColQuery = Add-CMDeviceCollectionQueryMembershipRule @CollectionRule
            }
        }
        If ($Collection) {
            # Move the collection into place
            Write-Verbose "Moving collection into administrative folder"
            $ModelFolder = "Client Services\Client Administration\Bios Operations\Models"
            Move-CMObject -FolderPath "$($SiteCode):\DeviceCollection\$ModelFolder" `
                -ObjectID $Collection.CollectionID
        }
    }
    End {
        Pop-Location
    }
}

Get-DriverPackageModels @SCCMOpts |
Select-NonExsitentialCollections @SCCMOpts |
New-ModelCollection @PSBoundParameters