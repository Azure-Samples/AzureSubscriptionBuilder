# Parameters for script
param ([string] $businessUnit)

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

# Query to see if management group already exists
$mgmtGroup = Get-AzManagementGroup `
    -GroupName "$businessUnit-mgmtgrp" `
    -ErrorAction SilentlyContinue

if (!$mgmtGroup) {
    # Create management group
    $mgmtGroup = New-AzManagementGroup `
    -GroupName "$businessUnit-mgmtgrp" `
    -DisplayName "$businessUnit-mgmtgrp" `
    -ParentId "/providers/Microsoft.Management/managementGroups/rootMgmtGroup"
    
    Write-Verbose -Message "successfully created management group: $($mgmtGroup.Name)"

} else {
    Write-Warning -Message "$($mgmtGroup.DisplayName) already exists, proceeding to subscription creation..."
    Write-Verbose -Message "$($mgmtGroup.DisplayName) already exists, proceeding to subscription creation..."
}

# Output management group and subscription id information in JSON format
$objOut = [PSCustomObject]@{

    managementGroupName = $mgmtGroup.Name

}

Write-Output ( $objOut | ConvertTo-Json)
