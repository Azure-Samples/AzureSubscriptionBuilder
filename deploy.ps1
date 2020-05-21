###############################################################################################################
##
## Azure Subscription Builder Deployment Script
##
###############################################################################################################

# Intake and set parameters
$parameters = Get-Content ./deployParams.json | ConvertFrom-Json
$location = $parameters.location
$rootManagementGroup = $parameters.rootManagementGroup
$Name = $parameters.Name.ToLower()
$pfxCertPath = $parameters.pfxCertPath
$certPass = ConvertTo-SecureString $parameters.certPass -AsPlainText -Force
$tenantId = (Get-AzContext).Tenant.Id
$subId = (Get-AzContext).Subscription.Id
$baseStorageUrl = "https://$($Name)stgacct.blob.core.windows.net/sub-builder"
$logFile = "./deploy_$(get-date -format `"yyyyMMddhhmmsstt`").log"

# Set preference variables
$ErrorActionPreference = "Stop"

#Validate Name
Function ValidateName {
    if ($Name.length -gt 17) {
        Write-Warning "Name is too long, please shorten to under 17 characters"
        exit
    }
}

ValidateName $Name

# Validate Location
$validLocations = Get-AzLocation
Function ValidateLocation {
    if ($location -in ($validLocations | Select-Object -ExpandProperty Location)) {
        foreach ($l in $validLocations) {
            if ($location -eq $l.Location) {
                $script:locationName = $l.DisplayName
            }
        }
    }
    else {
        Write-Host "ERROR: Location provided is not a valid Azure Region!" -ForegroundColor red
        exit
    }
}

ValidateLocation $location

# Create resource group if it doesn't already exist
$rgcheck = Get-AzResourceGroup -Name "$Name-rg" -ErrorAction SilentlyContinue
if (!$rgcheck) {
    Write-Host "INFO: Creating new resource group: $Name-rg" -ForegroundColor green
    Write-Verbose -Message "Creating new resource group: $Name-rg"
    New-AzResourceGroup -Name "$Name-rg" -Location $location

}
else {
    Write-Warning -Message "Resource Group: $Name-rg already exists. Continuing with deployment..."

}

# Gather enrollment account information
Write-Host "INFO: Gathering EA Information" -ForegroundColor green

function Show-Menu
{
    param ([string]$Title)

    Write-Host "======== $Title ========"

    $Menu = @{}

    try {
        (Get-AzEnrollmentAccount).ObjectId | ForEach-Object -Begin {$i = 1} {

            Write-Host "Press '$i' for: $_"
            $Menu.add("$i",$_)
            $i++
        }

        Write-Host "Q: Press 'Q' to quit."

        $Selection = Read-Host "Please make a selection"

        if ($Selection -eq 'Q') { return } else { $Menu.$Selection }
    }
    catch {
        $_ | Out-File -FilePath $logFile -Append
        Write-Host "ERROR: Unable to retrieve Enrollment Account information due to an exception, see $logFile for detailed information!" -ForegroundColor red
        exit

    }
}

$eaObjectId = Show-Menu -Title 'Enterprise Agreement Enrollments'

if (!$eaObjectId) {
    Write-Warning -Message "No Enterprise Agreement Enrollment was selected, exiting deployment!"
    exit

}
else {
    Write-Host "INFO: Proceeding with EA Enrollment: $eaObjectId" -ForegroundColor green

}

# Offer optional Web Front end
Write-Host "======== Front End Selection ========"

Write-Host "Would you like to deploy this package with the included optional Web Front End? (Default is No)"

try {
    [ValidateSet('Y', 'N')] $selection = Read-Host " ( Y / N ) "
    switch ($selection)
    {
        Y {Write-Host "INFO: You chose 'Yes', included web front end will be deployed" -ForegroundColor Green; $webFrontEnd = $true}
        N {Write-Warning "You chose 'No', included web front end will not be deployed"; $webFrontEnd = $false}
        Default {Write-Warning "No selection was made, skipping front end deployment.."; $webFrontEnd = $false}
    }
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Front End Selection failed due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit

}


# Build azure run as service principal certificate
Write-Host "INFO: Building Azure Run As Certificate" -ForegroundColor green
Write-Verbose -Message "Building Azure Run As Certificate"
$flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable `
    -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet `
    -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet

try {
    $PfxCert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($pfxCertPath, $certPass, $flags)

}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to create PFX certificate due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit

}
# Export certificate and convert into base 64 string
$Base64Value = [System.Convert]::ToBase64String($PfxCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12))
$Thumbprint = $PfxCert.Thumbprint

try {
    # Create azure service principal
    Write-Host "INFO: Creating new Azure Service Principal" -ForegroundColor green
    Write-Verbose -Message "Creating new Azure Service Principal"
    $now = [System.DateTime]::Now
    $6mofrmnow = $now.AddMonths(6)
    $sp = New-AzADServicePrincipal `
    -DisplayName $Name `
    -CertValue $Base64Value `
    -StartDate $now `
    -EndDate $6mofrmnow
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to create Service Principal due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit

}

try {
    # Add client secret to service principal
    Write-Host "INFO: Creating Azure Service Principal client secret" -ForegroundColor green
    Write-Verbose -Message "Creating Azure Service Principal client secret"
    New-AzADAppCredential `
    -DisplayName $sp.DisplayName `
    -Password $certPass `
    -StartDate $now `
    -EndDate $6mofrmnow
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to create Service Principal secret due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit

}


# Check to see if service principal already has management group owner role assigned
$spMgmtGroupRole = Get-AzRoleAssignment `
-RoleDefinitionName "Owner" `
-ObjectId $sp.Id `
-Scope "/providers/Microsoft.Management/managementGroups/$rootManagementGroup"

if ($spMgmtGroupRole) {
    Write-Warning -Message "Owner Role for Management Group: $rootManagementGroup is already assigned to $($sp.DisplayName), continuing with deployment..."

} 
else {
    Write-Host "INFO: Assigning Owner Role to Service Principal: $($sp.DisplayName) for Management Group: $rootManagementGroup" -ForegroundColor green
    do {
        # Assign owner role to service principal for management group
        Write-Verbose -Message "Assigning Owner Role to Service Principal: $($sp.DisplayName) for Management Group: $rootManagementGroup"
        $mgmtGroupRole = New-AzRoleAssignment `
        -RoleDefinitionName "Owner" `
        -ObjectId $sp.Id `
        -Scope "/providers/Microsoft.Management/managementGroups/$rootManagementGroup" `
        -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 10

    } while (!$mgmtGroupRole)
}

# Check to see if service principal already has enrollment account owner role assigned
$spEaRole = Get-AzRoleAssignment `
-RoleDefinitionName "Owner" `
-ObjectId $sp.Id `
-Scope "/providers/Microsoft.Billing/enrollmentAccounts/$eaObjectId"

if ($spEaRole) {
    Write-Warning -Message "Owner Role for Enrollment Account: $eaObjectId is already assigned to $($sp.DisplayName), continuing with deployment..."

} 
else {
    Write-Host "INFO: Assigning Owner Role to Service Principal: $($sp.DisplayName) for Enrollment Account: $eaObjectId" -ForegroundColor green
    do {
        # Assign owner role to service principal for enrollment account
        Write-Verbose -Message "Assigning EA Owner Role to Service Principal"
        $eaRole = New-AzRoleAssignment `
        -RoleDefinitionName "Owner" `
        -ObjectId $sp.Id `
        -Scope "/providers/Microsoft.Billing/enrollmentAccounts/$eaObjectId" `
        -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 10

    } while (!$eaRole)

}

# Obtain current user principal name for granting full access to Key Vault and secret
Write-Host "INFO: Obtaining current user context for granting administrative rights to Key Vault" -ForegroundColor green
Write-Verbose -Message "Obtaining current user context for granting administrative rights to Key Vault"
$context = Get-AzContext
$owner = Get-AzADUser -UserPrincipalName $context.Account.Id

try {
    # Deploy ARM template to create log analytics workspace
    Write-Host "INFO: Deploying ARM template to create Log Analytics Workspace" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM template to create Log Analytics Workspace"
    $workspaceParams = @{
        'workspaceName' = "$Name-workspace"
    }
    New-AzResourceGroupDeployment `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./infra_templates/monitor/logAnalyticsWorkspace.json `
    -TemplateParameterObject $workspaceParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy Log Analytics Workspace ARM template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit

}

try {
    # Deploy ARM to create Key Vault and Secret
    Write-Host "INFO: Deploying ARM template to create Key Vault and Secret" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM template to create Key Vault and Secret"
    $keyVaultParams = @{
        'keyVaultName' = "$Name-keyvault";
        'diagSettingsName' = "$Name-keyvault-diagsettings";
        'workspaceId' = "/subscriptions/$subId/resourcegroups/$Name-rg/providers/microsoft.operationalinsights/workspaces/$Name-workspace";
        'ownerObjectId' = $owner.Id;
        'spObjectId' = $sp.Id;
        'secretName' = "$Name-secret";
        'secretValue' = $parameters.certPass # Need to pass string version as ARM deployment will convert to secure string
    }
    New-AzResourceGroupDeployment `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./infra_templates/keyVault/keyVault.json `
    -TemplateParameterObject $keyVaultParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy Key Vault ARM template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit

}

try {
    # Deploy ARM template to create storage account and blob container
    Write-Host "INFO: Deploying ARM template to create Storage Account and Blob Container" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM template to create Storage Account and Blob Container"
    $storageParams = @{
        'storageAccountName' = "$($Name)stgacct"
    }
    New-AzResourceGroupDeployment `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./infra_templates/storageAccount/storageAcct.json `
    -TemplateParameterObject $storageParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy Storage Account ARM template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit

}

# Get storage account context for artifact upload
Write-Host "INFO: Obtaining Storage Account context for artifact uploads..." -ForegroundColor green
Write-Verbose -Message "Obtaining Storage Account context for artifact uploads..."
$storageAccount = Get-AzStorageAccount -ResourceGroupName "$Name-rg" -Name "$($Name)stgacct"

if (!$storageAccount) {
    Write-Host "ERROR: Unable to obtain storage context, exiting script!" -ForegroundColor red
    exit

} 
else {
    try {
        # Find/replace "rootMgmtGroup" for one provided in deployParams.json
        Write-Host "INFO: Dynamically updating automation runbooks" -ForegroundColor green
        Write-Verbose -Message "Dynamically updating automation runbooks"
        Get-ChildItem `
        -File `
        -Path ./runbooks/* `
        -Exclude *-dynamic.ps1 | `
        ForEach-Object {
            $findString = [regex]::escape('rootMgmtGroup')
            $newRunbook = @()
            Get-Content $_ | `
            ForEach-Object {
                if ($_ -match $findString) {
                    $newRunbook += ($_ -replace $findString, $rootManagementGroup)
                }
                else {
                    $newRunbook += $_
                }
            }
            $newRunbook | set-content "./runbooks/$($_.BaseName)-dynamic.ps1"
        }
    }
    catch {
        $_ | Out-File -FilePath $logFile -Append
        Write-Host "ERROR: Unable to dynamically update Automation Runbooks due to an exception, see $logFile for detailed information!" -ForegroundColor red
        exit

    }

    try {
        # Upload powershell runbooks to storage account
        Write-Host "INFO: Uploading automation runbooks" -ForegroundColor green
        Write-Verbose -Message "Uploading automation runbooks"
        Get-ChildItem `
        -File `
        -Path ./runbooks/* `
        -Include *-dynamic.ps1 | `
        ForEach-Object {
            Set-AzStorageBlobContent `
            -Container "sub-builder" `
            -File "$_" `
            -Blob "runbooks/$($_.Name)" `
            -Context $storageAccount.Context
        }
    }
    catch {
        $_ | Out-File -FilePath $logFile -Append
        Write-Host "ERROR: Unable to upload Automation Runbooks due to an exception, see $logFile for detailed information!" -ForegroundColor red
        exit

    }
}

# Import blueprint if it doesn't already exist
$blueprint =  Get-AzBlueprint `
-ManagementGroupId $rootManagementGroup `
-Name "sub-poc-blueprint" `
-ErrorAction SilentlyContinue

if ($blueprint) {
    Write-Warning -Message "Blueprint has already been imported into Management Group: $rootManagementGroup, continuing with deployment..."

} 
else {
    try {
        Write-Host "INFO: Importing Blueprint: 'sub-poc-blueprint' into $rootManagementGroup" -ForegroundColor green
        Write-Verbose -Message "Importing Blueprint: 'sub-poc-blueprint' into $rootManagementGroup"
        Import-AzBlueprintWithArtifact `
        -Name "sub-poc-blueprint" `
        -ManagementGroupId $rootManagementGroup `
        -InputPath ./blueprints/poc-blueprint/

        $blueprint =  Get-AzBlueprint `
        -ManagementGroupId $rootManagementGroup `
        -Name "sub-poc-blueprint"

        # Publish blueprint
        Write-Host "INFO: Publishing Blueprint: sub-poc-blueprint to Management Group: $rootManagementGroup" -ForegroundColor green
        Write-Verbose -Message "Publishing Blueprint: sub-poc-blueprint to Management Group: $rootManagementGroup"
        Publish-AzBlueprint `
        -Blueprint $blueprint `
        -Version '1.0'
    }
    catch {
        $_ | Out-File -FilePath $logFile -Append
        Write-Host "ERROR: Unable to publish Blueprint due to an exception, see $logFile for detailed information!" -ForegroundColor red
        exit

    }
}

try {
    # Deploy ARM template to create automation account, runbook, and modules
    Write-Host "INFO: Deploying ARM template to create Automation Account, Modules and Runbooks" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM Template to create Automation Account, Modules and Runbooks"
    $automationParams = @{
        'baseStorageUrl' = $baseStorageUrl;
        'automationAccountName' = "$Name-autoacct";
        'diagSettingsName' = "$Name-autoacct-diagsettings";
        'workspaceId' = "/subscriptions/$subId/resourcegroups/$Name-rg/providers/microsoft.operationalinsights/workspaces/$Name-workspace";
        'appId' = $sp.ApplicationId;
        'tenantId' = $tenantId;
        'thumbprint' = $Thumbprint;
        'certValue' = $Base64Value
    }
    New-AzResourceGroupDeployment `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./infra_templates/automationAccount/automationAcct.json `
    -TemplateParameterObject $automationParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy Automation Account ARM Template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit
}

try {
    # Deploy ARM template to create Cosmos DB Account and Database
    Write-Host "INFO: Deploying ARM template to create Cosmos DB Database" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM template to create Cosmos DB Database"
    $dbParams = @{
        'containerName' = "$Name-container";
        'dbAccountName' = "$Name-dbacct";
        'dbName' = "$Name-db";
        'diagSettingsName' = "$Name-dbacct-diagsettings";
        'locationName' = "$locationName";
        'workspaceId' = "/subscriptions/$subId/resourcegroups/$Name-rg/providers/microsoft.operationalinsights/workspaces/$Name-workspace"
    }
    New-AzResourceGroupDeployment `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./infra_templates/cosmosDB/cosmosDb.json `
    -TemplateParameterObject $dbParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy Cosmos DB ARM template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit

}

try {
    # Build Logic App parameter file dynamically
    Write-Host "INFO: Deploying ARM template to create Logic App Workflow" -ForegroundColor green
    Write-Verbose -Message "Building Logic App Parameter file... "
    $laParamObj = (Get-Content -Path ./infra_templates/logicApp/LogicAppParams.json | ConvertFrom-Json)
    $laParams = $laParamObj.parameters
    $laParams.logicAppName.value = "$Name-logicapp"
    $laParams.dbAccountName.value = "$Name-dbacct"
    $laParams.dbContainerName.value = "$Name-container"
    $laParams.dbName.value = "$Name-db"
    $laParams.diagSettingsName.value = "$Name-logicapp-diagsettings"
    $laParams.workspaceId.value = "/subscriptions/$subId/resourcegroups/$Name-rg/providers/microsoft.operationalinsights/workspaces/$Name-workspace"
    $laParams.automationAccountName.value = "$Name-autoacct"
    $laParams.appId.value = $sp.ApplicationId
    $laParams.appSecret.reference.keyVault.id = "/subscriptions/$subId/resourceGroups/$Name-rg/providers/Microsoft.KeyVault/vaults/$Name-keyvault"
    $laParams.appSecret.reference.secretName = "$Name-secret"
    $laParams.tenantId.value = $tenantId
    $laParamObj | ConvertTo-Json -Depth 100 | Out-File -FilePath "./infra_templates/logicApp/LogicAppDynamicParams.json" -Force

    # Deploy ARM template to create logic app workflow
    Write-Verbose -Message "Deploying ARM Template to create logic app workflow"
    $la = New-AzResourceGroupDeployment `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./infra_templates/logicApp/LogicApp.json `
    -TemplateParameterFile ./infra_templates/logicApp/LogicAppDynamicParams.json
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy Logic App ARM Template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit
}

if ($webFrontEnd -eq $true) {
    try {
        # Enable Static Website and upload contents if selected
        # Gather Logic App endpoint and edit/create the "webFormDynamic.html" for website content
        $laEndpoint = $la.Outputs.Values.Value

        $test_regex = [regex]::escape('fetch(')
        $la_regex = [regex]::escape('LogicAppURL')
        $new_html = @()
        $test = $false

        # Replace 'LogicAppURL' with actual Logic App endpoint.
        get-content ./webFrontEnd/webForm.html |
        ForEach-Object {
            if ($_ -match $test_regex){
                $test = $true
            }
                if ($test){
                    if ($_ -match $la_regex){
                        $new_html += ($_ -replace $la_regex, $laEndpoint)
                    }
                else {$new_html += $_}
                }
            else {$new_html += $_}
        }
        $new_html | set-content ./webFrontEnd/deployments/webFormDynamic.html
    }
    catch {
        $_ | Out-File -FilePath $logFile -Append
        Write-Host "ERROR: Unable to update webFormDynamic.html with Logic App endpoint, see $logFile for detailed information!" -ForegroundColor red
        exit

    }

    try {
        Write-Host "INFO: Enabling static website frontend in Storage Account: $($storageAccount.StorageAccountName)" -ForegroundColor Green
        Write-Verbose -Message "Enabling static website frontend in Storage Account: $($storageAccount.StorageAccountName)"
        Enable-AzStorageStaticWebsite `
        -Context $storageAccount.Context `
        -IndexDocument webFormDynamic.html `
        -ErrorDocument404Path errorPage.html
    }
    catch {
        $_ | Out-File -FilePath $logFile -Append
        Write-Host "ERROR: Unable to enable static website frontend in Storage Account due to an exception, see $logFile for detailed information!" -ForegroundColor red
        exit

    }

    try {
        Write-Host "INFO: Uploading static website content to Storage Account: $($storageAccount.StorageAccountName)" -ForegroundColor Green
        Write-Verbose -Message "Uploading static website content to Storage Account: $($storageAccount.StorageAccountName)"
        Get-ChildItem `
        -File `
        -Path ./webFrontEnd/deployments/ | `
        ForEach-Object {
            Set-AzStorageBlobContent `
            -Container `$web `
            -File "$_" `
            -Blob "$($_.Name)" `
            -Context $storageAccount.Context `
            -Properties @{"ContentType" = "text/html"}
        }

        Set-AzStorageBlobContent `
        -Container `$web `
        -File "./images/website/spring-cloud.jpg" `
        -Blob "spring-cloud.jpg" `
        -Context $storageAccount.Context `
        -Properties @{"ContentType" = "image/jpeg"}

        Write-Host "INFO: Static Website URL is: $($storageAccount.PrimaryEndpoints.Web)" -ForegroundColor green

    }
    catch {
        $_ | Out-File -FilePath $logFile -Append
        Write-Host "ERROR: Unable to upload static website content to Storage Account due to an exception, see $logFile for detailed information!" -ForegroundColor red
        exit
    }
} 
else {
    Write-Warning -Message "Front end deployment is being skipped based on earlier selection"
}

Write-Host "INFO: Subscription Builder deployment has completed successfully!" -ForegroundColor green
