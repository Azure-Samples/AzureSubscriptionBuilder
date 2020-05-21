# Parameters for script
param ([string] $businessUnit, $blueprintName, $location, $subId)

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

# Gather blueprint parameters
$params = @{ location = $location }
Write-Verbose -Message "params = $params"

# Get timestamp for blueprint assignment
$date = Get-Date -Format "yyyyMMddTHHmmss"
$assignmentName = "$businessUnit-AssignBlueprint-$date"
Write-Verbose -Message "Assignment Name = $assignmentName"

# Get blueprint object
Write-Verbose -Message "Gathering Blueprint Object information..."
$blueprintObject =  Get-AzBlueprint `
-ManagementGroupId rootMgmtGroup `
-Name $blueprintName `
-ErrorAction SilentlyContinue

if (!$blueprintObject) {
    $errorMessage = "Blueprint: $blueprintName could not be found in management group: rootMgmtGroup"
    Write-Error -Message $errorMessage
    throw $errorMessage
    
} else {
    Write-Verbose -Message $blueprintObject

}

# Assign blueprint
$assignBlueprintSuccessful = $false
$assignBlueprintAttempts = 1

while (-not $assignBlueprintSuccessful) {
    try {
        $blueprintAssignment = New-AzBlueprintAssignment `
        -Blueprint $blueprintObject `
        -Name $assignmentName `
        -Location $location `
        -SubscriptionId $subId `
        -Parameter $params
    
        Write-Verbose -Message "Applying blueprint assignment: $assignmentName to subscription: $subId"

        $assignBlueprintSuccessful = $true
    
    }
    catch {
        if ($assignBlueprintAttempts -lt $maxRetryAttempts) {
            Write-Warning -Message "We've hit an exception: $($_.Exception.Message)...retry attempt $assignBlueprintAttempts..."
            $assignBlueprintSleep = [math]::Pow($assignBlueprintAttempts,2)

            Start-Sleep -Seconds $assignBlueprintSleep

            $assignBlueprintAttempts ++
        }
        else {
            Write-Error -Message $_.Exception
            throw $_.Exception

        }    
    }
}

do {
    $provisioningState = $(Get-AzBlueprintAssignment `
    -Name $blueprintAssignment.Name `
    -SubscriptionId $subId).ProvisioningState

    Start-Sleep -Seconds 5
    
}
while ($provisioningState -ne "Succeeded")

Write-Verbose -Message "Blueprint assignment: $($blueprintAssignment.Name) has been applied to subscription: $subId"

$objOut = [PSCustomObject]@{
    
    blueprintAssignment = $blueprintAssignment.Id

}

Write-Output ( $objOut | ConvertTo-Json)
