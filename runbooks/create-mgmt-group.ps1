# Parameters for script
param ([string] $businessUnit)

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

# Query to see if management group already exists
$mgmtGroup = Get-AzManagementGroup `
    -GroupName "$businessUnit-mgmtgrp" `
    -ErrorAction SilentlyContinue

if (!$mgmtGroup) {
    $mgmtGroupCreate = $false
    $mgmtGroupCreateAttempts = 1

    while (-not $mgmtGroupCreate) {
        try {
            # Create management group
            $mgmtGroup = New-AzManagementGroup `
            -GroupName "$businessUnit-mgmtgrp" `
            -DisplayName "$businessUnit-mgmtgrp" `
            -ParentId "/providers/Microsoft.Management/managementGroups/rootMgmtGroup"
            
            Write-Verbose -Message "successfully created management group: $($mgmtGroup.Name)"

            $mgmtGroupCreate = $true
        }
        catch {
            If ($mgmtGroupCreateAttempts -le $maxRetryAttempts) {
                Write-Warning -Message "We've hit an exception: $($_.Exception.Message) after attempt $mgmtGroupCreateAttempts..."
                $mgmtGroupCreateSleep = [math]::Pow($mgmtGroupCreateAttempts,2)
    
                Start-Sleep -Seconds $mgmtGroupCreateSleep
    
                $mgmtGroupCreateAttempts ++
            }
            else {
                $errorMessage = "Unable to create management group: $businessUnit-mgmtgrp due to exception: $($_.Exception.Message)"
                Write-Error -Message $errorMessage
                throw $errorMessage

            }
        }
    }
} 
else {
    Write-Warning -Message "$($mgmtGroup.DisplayName) already exists, proceeding to subscription creation..."

}

# Output management group and subscription id information in JSON format
$objOut = [PSCustomObject]@{

    managementGroupName = $mgmtGroup.Name

}

Write-Output ( $objOut | ConvertTo-Json)
