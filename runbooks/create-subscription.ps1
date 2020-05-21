# Parameters for script
param ([string] $businessUnit, $mgmtGroupName, $offerType)

# Set preference variables
$ErrorActionPreference = "Stop"

# Authenticate to azure
$connectionName = "AutomationSP"

try
{
    # Get the automation account connection
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName

    Write-Verbose -Message "Logging in to Azure..."
    Connect-AzAccount -Tenant $servicePrincipalConnection.TenantID `
    -ApplicationId $servicePrincipalConnection.ApplicationID   `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
    -ServicePrincipal `
    | Out-Null
    Write-Verbose -Message "Logged in."
}
catch {
    if (!$servicePrincipalConnection)
    {
        $errorMessage = "Connection $connectionName not found."
        Write-Error -Message $errorMessage
        throw $errorMessage
    } else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# Get enrollment account object id
$ea = Get-AzEnrollmentAccount

Write-Verbose -Message "The Enrollment Account ID is $($ea.ObjectId)"

# Create subscription
$subCreateComplete = $false
$subCreateAttempts = 1

while (-not $subCreateComplete) {
    try {
        $sub = New-AzSubscription `
        -OfferType $offerType `
        -Name "$businessUnit-subscription" `
        -EnrollmentAccountObjectId $ea.ObjectId
    
        Write-Verbose -Message "successfully created subscription: $($sub.Id)"

        $subCreateComplete = $true
        
    }
    catch {
        if ($_.Exception.Message.Contains("status code '429'")) {
            Write-Warning -Message "Experiencing rate limiting...retry attempt $subCreateAttempts..."
            $subCreateSleep = [math]::Pow($subCreateAttempts,2)

            Start-Sleep -Seconds $subCreateSleep

            $subCreateAttempts ++
            
        }
        else {
            Write-Error -Message $_.Exception
            throw $_.Exception
            
        }
    }
}

# Move subscription into management group
try {
    New-AzManagementGroupSubscription `
    -GroupName $mgmtGroupName `
    -SubscriptionId $sub.Id

    Write-Verbose -Message "moving subscription: $($sub.Id) into management group: $mgmtGroupName"

}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception

}

# Validate subscription has been successfully moved into management group
$subMoveComplete = $false
$subMoveValidateAttempts = 1

while (-not $subMoveComplete) {
    try {
        $mgmtGrpInfo = Get-AzManagementGroup `
        -GroupName $mgmtGroupName `
        -Expand
    
        if ($mgmtGrpInfo.Children | Where-Object {$_.Name -eq $sub.Id }) {
            $subMoveComplete = $true
            Write-Verbose -Message "successfully moved subscription: $($sub.Id) into management group: $mgmtGroupName"

        }
        else {
            Write-Warning -Message "Subscription has not moved yet...retry validation attempt $subMoveValidateAttempts..."
            $subMoveSleep = [math]::Pow($subMoveValidateAttempts,2)

            Start-Sleep -Seconds $subMoveSleep

            $subMoveValidateAttempts ++
    
        }
    }
    catch {
        Write-Error -Message $_.Exception
        throw $_.Exception

    }
}

# Output subscription id information in JSON format
$objOut = [PSCustomObject]@{

    subscriptionId = $sub.Id

}

Write-Output ( $objOut | ConvertTo-Json)
