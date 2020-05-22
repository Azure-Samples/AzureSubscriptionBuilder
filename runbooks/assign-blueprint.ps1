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

# Execute blueprint assignment
function assignBlueprint {
    $assignBlueprintExecute = $false
    $assignBlueprintExecuteAttempts = 1
    
    while (-not $assignBlueprintExecute) {
        try {
            $script:blueprintAssignment = New-AzBlueprintAssignment `
            -Blueprint $blueprintObject `
            -Name $assignmentName `
            -Location $location `
            -SubscriptionId $subId `
            -Parameter $params
        
            Write-Verbose -Message "Assigning blueprint assignment: $assignmentName to subscription: $subId"
    
            $assignBlueprintExecute = $true
        
        }
        catch {
            if ($assignBlueprintExecuteAttempts -le $maxRetryAttempts) {
                Write-Warning -Message "We've hit an exception: $($_.Exception.Message) after attempt $assignBlueprintExecuteAttempts..."
                $assignBlueprintExecuteSleep = [math]::Pow($assignBlueprintExecuteAttempts,2)
    
                Start-Sleep -Seconds $assignBlueprintExecuteSleep
    
                $assignBlueprintExecuteAttempts ++
            }
            else {
                $errorMessage = "Unable to execute blueprint assignment due to exception: $($_.Exception.Message)"
                Write-Error -Message $errorMessage
                throw $errorMessage
    
            }    
        }
    }
}

assignBlueprint $blueprintObject $assignmentName $location $subId $params $maxRetryAttempts

#validate blueprint assignment
$assignBlueprintValidate = $false
$assignBlueprintValidateAttempts = 1

while (-not $assignBlueprintValidate) {
    try {
        $provisioningState = $(Get-AzBlueprintAssignment `
        -Name $blueprintAssignment.Name `
        -SubscriptionId $subId).ProvisioningState
    }
    catch {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }

    if ($provisioningState -eq "Failed") {
        if ($assignBlueprintValidateAttempts -le $maxRetryAttempts) {
            Write-Warning -Message "Blueprint assignment failed after attempt $assignBlueprintValidateAttempts..."
            assignBlueprint $blueprintObject $assignmentName $location $subId $params $maxRetryAttempts

            $assignBlueprintValidateAttempts ++

        }
        else {
            $errorMessage = "Unable to assign Blueprint after $assignBlueprintValidateAttempts attempts"
            Write-Error -Message $errorMessage
            throw $errorMessage

        }
    }
    elseif ($provisioningState -eq "Succeeded") {
        Write-Verbose -Message "Blueprint assignment: $($blueprintAssignment.Name) has been assigned to subscription: $subId successfully"
        $assignBlueprintValidate = $true

    }
    else {
        Start-Sleep -Seconds 10

    }
}

$objOut = [PSCustomObject]@{
    
    blueprintAssignment = $blueprintAssignment.Id

}

Write-Output ( $objOut | ConvertTo-Json)
