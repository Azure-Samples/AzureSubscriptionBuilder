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

# Check to see if Blueprint assignment exists or not
function doesBlueprintAssignmentExist {
    $success = $false
    $attempts = 1
    while (-not $success) {
        $blueprintAssignment = Get-AzBlueprintAssignment `
        -Name $assignmentName `
        -SubscriptionId $subId `
        -ErrorVariable $errorVar `
        -ErrorAction SilentlyContinue 

        Write-Verbose -Message "Checking to see if Blueprint assignment: $assignmentName exists..."

        if (!$blueprintAssignment) {
            if ($errorVar[0].ToString().Contains("Assignment '$assignmentName' could not be found in subscription '$subId'")) {
                Write-Verbose -Message "Blueprint assignment does not already exist, proceeding with assignment..."

                $success = $true
                return "notAssigned"
            }
            else {
                if ($attempts -le $maxRetryAttempts) {
                    Write-Warning -Message "Unable to check whether assignment exists due to exception: $(($errorVar[0].ToString() -split '\n')[0]) after attempt $attempts..."
                    $sleep = [math]::Pow($attempts,2)
            
                    Start-Sleep -Seconds $sleep
        
                    $attempts ++
                }
                else {
                    Write-Error -Message "Unable to check whether assignment exists due to exception: $(($errorVar[0].ToString() -split '\n')[0]) after $attempts attempts"
                    Throw $errorVar

                }
            }

        }
        else {
            Write-Warning -Message "Blueprint Assignment: $(blueprintAssignment.Id) already exists in subscription: $subId...calling it done"
            $success = $true
            return "alreadyAssigned"

        }
    }
}

# Execute blueprint assignment
function executeBlueprintAssignment {
    $success = $false
    $attempts = 1
    
    while (-not $success) {
        try {
            $script:blueprintAssignment = New-AzBlueprintAssignment `
            -Blueprint $blueprintObject `
            -Name $assignmentName `
            -Location $location `
            -SubscriptionId $subId `
            -Parameter $params
        
            Write-Verbose -Message "Assigning blueprint assignment: $assignmentName to subscription: $subId"
    
            $success = $true

            return "assignmentExecutionSuceeded"
        
        }
        catch {
            if ($attempts -le $maxRetryAttempts) {
                Write-Warning -Message "We've hit an exception: $($_.Exception.Message) after attempt $attempts..."
                
                $sleep = [math]::Pow($attempts,2)
    
                Start-Sleep -Seconds $sleep
    
                $attempts ++
            }
            else {
                $errorMessage = "Unable to execute blueprint assignment due to exception: $($_.Exception.Message) after $attempts attempts"
                Write-Error -Message $errorMessage
                throw $errorMessage
    
            }
        }
    }
}

# Validate blueprint assignment
function validateBlueprintAssignment {
    $success = $false
    $attempts = 1
    
    while (!$success) {
        try {
            $provisioningState = $(Get-AzBlueprintAssignment `
            -Name $blueprintAssignment.Name `
            -SubscriptionId $subId).ProvisioningState

            Write-Verbose -Message "Obtaining provisioning state for Blueprint assignment: $($blueprintAssignment.Name)..."

            $success = $true
        }
        catch {
            if ($attempts -le $maxRetryAttempts) {
                Write-Warning -Message "Unable to validate assignment due to exception: $($_.Exception.Message) after attempt $attempts..."
                $sleep = [math]::Pow($attempts,2)
        
                Start-Sleep -Seconds $sleep
    
                $attempts ++
            }
            else {
                Write-Error -Message "Unable to validate assignment due to exception: $($_.Exception.Message) after $attempts attempts"
                throw $_.Exception

            }
        }
    
        if ($provisioningState -eq "Failed") {
            Write-Warning -Message "Blueprint assignment has $provisioningState"

            return $provisioningState

        }
        elseif ($provisioningState -eq "Succeeded") {
            Write-Verbose -Message "Blueprint assignment: $($blueprintAssignment.Name) $provisioningState and has been assigned to subscription: $subId successfully"
            
            return $provisioningState
    
        }
        else {
            Write-Warning -Message "Blueprint assignment is in a $provisioningState state..."

            return $provisioningState
    
        }
    }
}

doesBlueprintAssignmentExist $assignmentName $subId $maxRetryAttempts

executeBlueprintAssignment $blueprintObject $assignmentName $location $subId $params $maxRetryAttempts

validateBlueprintAssignment $blueprintAssignment $subId $maxRetryAttempts


$objOut = [PSCustomObject]@{
    
    blueprintAssignment = $blueprintAssignment.Id

}

Write-Output ( $objOut | ConvertTo-Json)
