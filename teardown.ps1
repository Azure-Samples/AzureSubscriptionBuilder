#####################################################################
##
## Azure Subscription Builder Teardown Script
##
#####################################################################

$parameters = Get-Content ./deployParams.json | ConvertFrom-Json
$Name = $parameters.Name.ToLower()
$logFile = "./teardown_$(get-date -format `"yyyyMMddhhmmsstt`").log"

# Set preference variables
$ErrorActionPreference = "Stop"

# Obtain resource group object
$rg = Get-AzResourceGroup -Name "$Name-rg" -ErrorAction SilentlyContinue
if ($rg) {
    try {
        # Delete resource group
        Write-Host "INFO: Deleting Resource Group: $Name-rg" -ForegroundColor green        
        $rg | Remove-AzResourceGroup -Force

    }
    catch {
        $_ | Out-File -FilePath $logFile -Append
        Write-Host "ERROR: Deletion of Resouce Group: $Name-rg has failed due to an exception, see $logFile for detailed information!" -ForegroundColor red
        exit 

    }
} else {
    Write-Warning -Message "Resource Group, $Name-rg, no longer exists"

}

# Obtain service principal object
$sp = Get-AzADApplication -DisplayName $Name -ErrorAction SilentlyContinue
if ($sp) {
    try {
        # Delete service principal
        Write-Host "INFO: Deleting Service Principal: $Name" -ForegroundColor green
        Remove-AzADApplication -DisplayName $sp.DisplayName -Force -PassThru

    }
    catch {
        $_ | Out-File -FilePath $logFile -Append
        Write-Host "ERROR: Deletion of Service Principal: $Name has failed due to an exception, see $logFile for detailed information!" -ForegroundColor red
        exit

    }
} else {
    Write-Warning -Message "Service Principal, $Name, no longer exists"

}

Write-Host "INFO: Subscription Builder infrastructure has been cleaned up!" -ForegroundColor green
