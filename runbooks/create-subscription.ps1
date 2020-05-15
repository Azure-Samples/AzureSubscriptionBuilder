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
try {
    $sub = New-AzSubscription `
    -OfferType $offerType `
    -Name "$businessUnit-subscription" `
    -EnrollmentAccountObjectId $ea.ObjectId

    Write-Verbose -Message "successfully created subscription: $($sub.Id)"
    
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception

}

# Move subscription into management group
try {
    New-AzManagementGroupSubscription `
    -GroupName $mgmtGroupName `
    -SubscriptionId $sub.Id

    Write-Verbose -Message "successfully moved subscription: $($sub.Id) into management group: $mgmtGroupName"

}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception

}

# Output subscription id information in JSON format
$objOut = [PSCustomObject]@{

    subscriptionId = $sub.Id

}

Write-Output ( $objOut | ConvertTo-Json)
