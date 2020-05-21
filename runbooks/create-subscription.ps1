# Parameters for script
param ([string] $businessUnit, $mgmtGroupName, $offerType)

# Set preference variables
$ErrorActionPreference = "Stop"

# Authenticate to azure
$connectionName = "AutomationSP"

# Max retry attempts for API calls
$maxRetryAttempts = 10

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
        if ($subCreateAttempts -lt $maxRetryAttempts) {
            Write-Warning -Message "We've hit an exception: $($_.Exception.Message)...retry attempt $subCreateAttempts..."
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
$subMoveExecute = $false
$subMoveExecuteAttempts = 1

while (-not $subMoveExecute) {
    try {
        New-AzManagementGroupSubscription `
        -GroupName $mgmtGroupName `
        -SubscriptionId $sub.Id
    
        Write-Verbose -Message "moving subscription: $($sub.Id) into management group: $mgmtGroupName"

        $subMoveExecute = $true
    
    }
    catch {
        if ($subMoveExecuteAttempts -lt $maxRetryAttempts) {
            Write-Warning -Message "We've hit an exception: $($_.Exception.Message)...retry attempt $subCreateAttempts..."
            $subMoveExecuteSleep = [math]::Pow($subMoveExecuteAttempts,2)

            Start-Sleep -Seconds $subMoveExecuteSleep

            $subMoveExecuteAttempts ++
        }
        else {
            Write-Error -Message $_.Exception
            throw $_.Exception
        
        }
    }
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
            Write-Verbose -Message "successfully moved subscription: $($sub.Id) into management group: $mgmtGroupName"

            $subMoveComplete = $true

        }
        else {
            Write-Warning -Message "Subscription has not moved yet...retry validation attempt $subMoveValidateAttempts..."
            $subMoveValidateSleep = [math]::Pow($subMoveValidateAttempts,2)

            Start-Sleep -Seconds $subMoveValidateSleep

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
