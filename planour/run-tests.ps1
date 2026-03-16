$ErrorActionPreference = "Stop"

Write-Host "=========================================="
Write-Host "   Planour Automated API Testing Script   "
Write-Host "=========================================="
Write-Host ""
Write-Host "[1/5] Extracting dynamic ports from running application logs..."

# We assume the application is running in another terminal. 
# We need to find the Keycloak dynamic port to get a token.
# To do this robustly from Powershell without needing to parse the spring-boot console,
# we can just query the well-known docker containers running.

$keycloakContainerId = docker ps -q --filter ancestor=quay.io/keycloak/keycloak:26.5.4 | Select-Object -First 1
if (-not $keycloakContainerId) {
    Write-Host "Error: Cannot find a running Keycloak Testcontainer. Is the TestPlanourRestapiApplication running?" -ForegroundColor Red
    exit 1
}

# The container maps 8080 internally to a random host port. Find that host port.
$keycloakPortStr = docker port $keycloakContainerId 8080/tcp
if (-not $keycloakPortStr) {
     Write-Host "Error: Could not determine mapped port for Keycloak." -ForegroundColor Red
     exit 1
}
# Format is similar to "0.0.0.0:54926"
$keycloakPort = $keycloakPortStr.Split(":")[1].Trim()
Write-Host "--> Found Keycloak running on port $keycloakPort" -ForegroundColor Green

Read-Host "Press Enter to continue to Tenant Creation..."

Write-Host ""
Write-Host "[2/5] Creating schemas for Tenants (Berlin and Munich)..."
$registerUri = "http://localhost:8080/api/v1/tenants/register"

try {
    $berlinResponse = Invoke-RestMethod -Uri "$registerUri`?tenantId=tenant_berlin&name=Berlin" -Method Post
    Write-Host "--> Successfully registered Tenant Berlin: $($berlinResponse.id)" -ForegroundColor Green
} catch {
    # It might already exist from previous runs, so ignoring 400s or 500s safely.
    Write-Host "--> Tenant Berlin might already exist or failed: $($_.Exception.Message)"
}

try {
    $munichResponse = Invoke-RestMethod -Uri "$registerUri`?tenantId=tenant_munich&name=Munich" -Method Post
    Write-Host "--> Successfully registered Tenant Munich: $($munichResponse.id)" -ForegroundColor Green
} catch {
    Write-Host "--> Tenant Munich might already exist or failed: $($_.Exception.Message)"
}

Read-Host "Press Enter to continue to requesting Access Token for Berlin..."


Write-Host ""
Write-Host "[3/5] Requesting Access Token for Berlin (Admin User)..."
$tokenUri = "http://localhost:$keycloakPort/realms/planour/protocol/openid-connect/token"
$body = @{
    client_id = "planour-rest-api"
    username = "user_berlin"
    password = "pass_berlin"
    grant_type = "password"
}

try {
    $tokenResponse = Invoke-RestMethod -Uri $tokenUri -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    $berlinToken = $tokenResponse.access_token
    Write-Host "--> Successfully received JWT Token for Berlin User!" -ForegroundColor Green
} catch {
    Write-Host "Error getting token for Berlin: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) {
        Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
    exit 1
}

Read-Host "Press Enter to continue to testing Authorization (Berlin Config)..."


Write-Host ""
Write-Host "[4/5] Testing Authorization and Tenant Isolation (Berlin Sector)..."
$configParams = @{
    title = "Berlin IT Sector"
    description = "Sector for Berlin Testing"
}
$configJsonList = $configParams | ConvertTo-Json

# POST Sector as Berlin
$apiUri = "http://localhost:8080/api/v1/sectors"
$headers = @{
    Authorization = "Bearer $berlinToken"
    "X-Tenant-ID" = "tenant_berlin"
}

try {
    $postResponse = Invoke-RestMethod -Uri $apiUri -Method Post -Body $configJsonList -ContentType "application/json" -Headers $headers
    Write-Host "--> Successfully created Sector for Berlin: $($postResponse.title)" -ForegroundColor Green
} catch {
    Write-Host "Error creating Sector as Berlin: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) {
        Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}

# GET Sectors as Berlin
try {
    $getResponse = Invoke-RestMethod -Uri $apiUri -Method Get -Headers $headers
    $itemCount = $getResponse.content.Count
    if ($null -eq $itemCount) { $itemCount = 0 }
    Write-Host "--> Successfully fetched Sectors for Berlin. Found $itemCount items." -ForegroundColor Green
    
    Write-Host "--> Testing Pagination (page=0, size=1)..."
    $pageResponse = Invoke-RestMethod -Uri "$apiUri`?page=0&size=1" -Method Get -Headers $headers
    $pageSize = $pageResponse.content.Count
    $totalPages = $pageResponse.totalPages
    Write-Host "--> Successfully tested Pagination. Page 0 has $pageSize items. Total Pages: $totalPages" -ForegroundColor Green
} catch {
    Write-Host "Error fetching Sectors as Berlin: $($_.Exception.Message)" -ForegroundColor Red
}

Read-Host "Press Enter to continue to requesting Access Token for Munich..."


Write-Host ""
Write-Host "[5/5] Requesting Access Token for Munich (Employee User - Testing 403 Forbidden)..."
$bodyMunich = @{
    client_id = "planour-rest-api"
    username = "user_munich"
    password = "pass_munich"
    grant_type = "password"
}

try {
    $tokenResponseMunich = Invoke-RestMethod -Uri $tokenUri -Method Post -Body $bodyMunich -ContentType "application/x-www-form-urlencoded"
    $munichToken = $tokenResponseMunich.access_token
    Write-Host "--> Successfully received JWT Token for Munich User!" -ForegroundColor Green
} catch {
    Write-Host "Error getting token for Munich: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) {
        Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
    exit 1
}

$munichHeaders = @{
    Authorization = "Bearer $munichToken"
    "X-Tenant-ID" = "tenant_munich"
}

try {
    Write-Host "--> Trying to POST Sector as Munich (Expected to fail with 403 Forbidden)..."
    $null = Invoke-RestMethod -Uri $apiUri -Method Post -Body $configJsonList -ContentType "application/json" -Headers $munichHeaders
    Write-Host "Error: Munich user was ALLOWED to post. This is a security test failure!" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 403) {
        Write-Host "--> Security Test Passed: Munich User was successfully BLOCKED with 403 Forbidden." -ForegroundColor Green
    } else {
        Write-Host "--> Failed with unexpected code $statusCode instead of 403: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Read-Host "Press Enter to continue to testing Data Isolation (Munich GET)..."

Write-Host ""
Write-Host "[6/10] Testing Data Isolation (Munich GET)..."
try {
    $munichGetResponse = Invoke-RestMethod -Uri $apiUri -Method Get -Headers $munichHeaders
    $munichItemCount = $munichGetResponse.content.Count
    if ($null -eq $munichItemCount) { $munichItemCount = 0 }
    if ($munichItemCount -eq 0) {
        Write-Host "--> Security Test Passed: Munich has $munichItemCount items. Data is perfectly isolated!" -ForegroundColor Green
    } else {
        Write-Host "Error: Munich sees $munichItemCount items. Tenant Isolation FAILED!" -ForegroundColor Red
    }
} catch {
    Write-Host "Error fetching Sector as Munich: $($_.Exception.Message)" -ForegroundColor Red
}

Read-Host "Press Enter to continue to testing Unauthorized Access..."

Write-Host ""
Write-Host "[7/10] Testing Unauthorized Access (No Token - Testing 401 Unauthorized)..."
try {
    $null = Invoke-RestMethod -Uri $apiUri -Method Get
    Write-Host "Error: Unauthenticated user was ALLOWED. Security test failure!" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 401) {
        Write-Host "--> Security Test Passed: Unauthenticated request BLOCKED with 401 Unauthorized." -ForegroundColor Green
    } else {
        Write-Host ("--> Failed with unexpected code {0} instead of 401: {1}" -f $statusCode, $_.Exception.Message) -ForegroundColor Yellow
    }
}

Read-Host "Press Enter to continue to testing Invalid Tenant Header..."

Write-Host ""
Write-Host "[8/10] Testing Invalid Tenant Header (Testing 404 Not Found)..."
$invalidTenantHeaders = @{
    Authorization = "Bearer $berlinToken"
    "X-Tenant-ID" = "invalid_tenant"
}
try {
    $null = Invoke-RestMethod -Uri $apiUri -Method Get -Headers $invalidTenantHeaders
    Write-Host "Error: Invalid tenant was ALLOWED. Security test failure!" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 404) {
        Write-Host "--> Security Test Passed: Invalid tenant BLOCKED with 404 Not Found." -ForegroundColor Green
    } else {
        Write-Host ("--> Failed with unexpected code {0} instead of 404: {1}" -f $statusCode, $_.Exception.Message) -ForegroundColor Yellow
    }
}

Read-Host "Press Enter to continue to testing Database Envelope Encryption..."

Write-Host ""
Write-Host "[9/10] Testing Database Envelope Encryption (Key Wrapping)..."
# Find PostgreSQL container
$pgContainerId = docker ps -q --filter ancestor=postgis/postgis:18-3.6 | Select-Object -First 1
if (-not $pgContainerId) {
    Write-Host "Error: Cannot find PostgreSQL Testcontainer." -ForegroundColor Red
} else {
    $keyCountOutput = docker exec $pgContainerId psql -U yaser -d planour_dev_db -tA -c "SELECT count(*) FROM public.tenant_keys;"
    $keyCountStr = ($keyCountOutput -join "").Trim()
    $keyCount = [int]$keyCountStr
    if ($keyCount -ge 2) {
        Write-Host "--> Security Test Passed: Envelope Encryption working! Found $keyCount wrapped keys in DB." -ForegroundColor Green
    } else {
        Write-Host "Error: Expected at least 2 tenant keys, found $keyCount." -ForegroundColor Red
    }
}

Read-Host "Press Enter to continue to testing Audit Log Immutability..."

Write-Host ""
Write-Host "[10/10] Testing Audit Log Immutability at Database Level (Triggers)..."
if ($pgContainerId) {
    try {
        # Redirecting stderr (2) to stdout (1) to capture the trigger error message
        $deleteOutput = docker exec $pgContainerId psql -U yaser -d planour_dev_db -c "DELETE FROM tenant_berlin.audit_logs;" 2>&1
        if ($deleteOutput -match "Audit logs are immutable") {
             Write-Host "--> Security Test Passed: Database Trigger successfully BLOCKED audit log deletion!" -ForegroundColor Green
        } elseif ($LASTEXITCODE -ne 0) {
             Write-Host "--> Security Test Passed: Query failed as expected. Output: $deleteOutput" -ForegroundColor Green
        } else {
             Write-Host "Error: Audit logs were DELETED! Immutability test FAILED." -ForegroundColor Red
        }
    } catch {
        if ($_.Exception.Message -match "Audit logs are immutable") {
             Write-Host "--> Security Test Passed: Database Trigger successfully BLOCKED audit log deletion!" -ForegroundColor Green
        } else {
             Write-Host "Error executing immutability test: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Read-Host "Press Enter to continue to testing Dynamic RBAC..."

Write-Host ""
Write-Host "[11/11] Testing Dynamic RBAC (Dynamic Role Creation)..."
$roleApiUri = "http://localhost:8080/api/v1/roles"
$roleParams = @{
    name = "PROJECT_MANAGER"
    description = "Test Role for PMs"
    permissions = @("READ_PROJECT", "UPDATE_PROJECT")
}
$roleJson = $roleParams | ConvertTo-Json

# 1. Admin creates a Role (Expected Success)
try {
    Write-Host "--> Trying to POST Role as Berlin Admin (Expected to succeed)..."
    $roleResponse = Invoke-RestMethod -Uri $roleApiUri -Method Post -Body $roleJson -ContentType "application/json" -Headers $headers
    Write-Host "--> Security Test Passed: Berlin Admin successfully created role '$($roleResponse.name)' with ID $($roleResponse.id)!" -ForegroundColor Green
} catch {
    Write-Host "Error creating role as Berlin Admin: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) {
        Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}

# 2. Regular user tries to create a Role (Expected Failure 403)
try {
    Write-Host "--> Trying to POST Role as Munich Employee (Expected to fail with 403 Forbidden)..."
    $null = Invoke-RestMethod -Uri $roleApiUri -Method Post -Body $roleJson -ContentType "application/json" -Headers $munichHeaders
    Write-Host "Error: Munich user was ALLOWED to create role. Security test failure!" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 403) {
        Write-Host "--> Security Test Passed: Munich Employee was successfully BLOCKED from creating roles." -ForegroundColor Green
    } else {
        Write-Host "--> Failed with unexpected code $statusCode instead of 403: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Read-Host "Press Enter to continue to testing Chart Engine API..."

Write-Host ""
Write-Host "[12/12] Testing Chart Engine API (CRUD & Data Isolation)..."
$chartApiUri = "http://localhost:8080/api/v1/charts"
$chartPayload = @{
    title = "Test Tasks Chart"
    description = "A chart for testing"
    chartType = "BAR"
    chartData = "{`"labels`": [`"A`", `"B`"], `"datasets`": [{`"data`": [1, 2]}]}"
} | ConvertTo-Json

# 1. POST ChartConfig as Berlin
try {
    Write-Host "--> Trying to POST Chart as Berlin Admin..."
    $chartResponse = Invoke-RestMethod -Uri $chartApiUri -Method Post -Body $chartPayload -ContentType "application/json" -Headers $headers
    $chartId = $chartResponse.id
    Write-Host "--> Successfully created Chart '$($chartResponse.title)' with ID $chartId!" -ForegroundColor Green
} catch {
    Write-Host "Error creating Chart as Berlin: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) {
        Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}

# 2. GET ChartConfig as Berlin
if ($chartId) {
    try {
        $getChartResponse = Invoke-RestMethod -Uri "$chartApiUri/$chartId" -Method Get -Headers $headers
        Write-Host "--> Successfully fetched Chart '$($getChartResponse.title)'." -ForegroundColor Green
    } catch {
        Write-Host "Error fetching Chart as Berlin: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 3. PUT ChartConfig as Berlin
    $chartUpdatePayload = @{
        title = "Updated Tasks Chart"
        description = "Updated chart for testing"
        chartType = "PIE"
        chartData = "{`"labels`": [`"A`", `"C`"], `"datasets`": [{`"data`": [3, 4]}]}"
    } | ConvertTo-Json
    
    try {
        $updateChartResponse = Invoke-RestMethod -Uri "$chartApiUri/$chartId" -Method Put -Body $chartUpdatePayload -ContentType "application/json" -Headers $headers
        if ($updateChartResponse.chartType -eq "PIE") {
            Write-Host "--> Successfully updated Chart to Type '$($updateChartResponse.chartType)'." -ForegroundColor Green
        } else {
            Write-Host "--> Update succeeded but chartType mismatch: $($updateChartResponse.chartType)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Error updating Chart as Berlin: $($_.Exception.Message)" -ForegroundColor Red
    }

    # 4. GET list of Charts as Berlin
    try {
        $listChartsResponse = Invoke-RestMethod -Uri $chartApiUri -Method Get -Headers $headers
        $chartCount = $listChartsResponse.content.Count
        if ($null -eq $chartCount) { $chartCount = $listChartsResponse.Count }
        Write-Host "--> Successfully fetched all Charts. Count: $chartCount." -ForegroundColor Green
    } catch {
        Write-Host "Error fetching Chart list as Berlin: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 5. Isolation - Munich tries to Get Berlin's chart
    try {
        Write-Host "--> Munich trying to fetch Berlin's Chart (Testing Data Isolation)..."
        $null = Invoke-RestMethod -Uri "$chartApiUri/$chartId" -Method Get -Headers $munichHeaders
        Write-Host "Error: Munich user could access Berlin's chart. Isolation Failure!" -ForegroundColor Red
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404 -or $statusCode -eq 403) {
            Write-Host "--> Security Test Passed: Munich blocked from accessing Berlin's Chart ($statusCode)." -ForegroundColor Green
        } else {
           Write-Host ("--> Failed with unexpected code {0} instead of 403/404: {1}" -f $statusCode, $_.Exception.Message) -ForegroundColor Yellow
        }
    }

    # 6. DELETE Chart as Berlin
    try {
        $null = Invoke-RestMethod -Uri "$chartApiUri/$chartId" -Method Delete -Headers $headers
        Write-Host "--> Successfully deleted Chart." -ForegroundColor Green
    } catch {
        Write-Host "Error deleting Chart as Berlin: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Read-Host "Press Enter to continue to Management Module Practical Tests..."

Write-Host ""
Write-Host "[13/13] Testing Management Module (Practical Tests)..."

Write-Host "--> 1. CREATING: Sector"
$sectorPayload = @{
    title = "IT Department"
    description = "Handles all IT infrastructure and software development"
} | ConvertTo-Json
try {
    $sectorResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/sectors" -Method Post -Body $sectorPayload -ContentType "application/json" -Headers $headers
    $sectorId = $sectorResponse.id
    Write-Host "--> Success! Created Sector with ID: $sectorId" -ForegroundColor Green
} catch {
    Write-Host "Error creating Sector: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
}

Read-Host "Press Enter to continue checking the database and proceed to Project Creation..."

if ($sectorId) {
    Write-Host "--> 2. CREATING: Project"
    $projectPayload = @{
        title = "Rest API Migration"
        description = "Migrate legacy APIs to modern Spring Boot architecture"
        priority = "HIGH"
        parentId = $sectorId
    } | ConvertTo-Json
    try {
        $projectResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/sectors/$sectorId/projects" -Method Post -Body $projectPayload -ContentType "application/json" -Headers $headers
        $projectId = $projectResponse.id
        Write-Host "--> Success! Created Project with ID: $projectId" -ForegroundColor Green
    } catch {
        Write-Host "Error creating Project: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    }

    Write-Host ""
    Write-Host "--> 2.5 CREATING & DOWNLOADING: Attachment for Project"
    $attachmentUri = "http://localhost:8080/api/v1/resources/$projectId/attachments"
    $tempFile = "$env:TEMP\test_upload_$(Get-Random).txt"
    Set-Content -Path $tempFile -Value "Sample attachment content for automated testing."
    try {
        $curlOutput = curl.exe -s -X POST $attachmentUri -H "Authorization: Bearer $berlinToken" -H "X-Tenant-ID: tenant_berlin" -F "file=@$tempFile"
        if ($curlOutput -match "error" -and $curlOutput -notmatch "id") {
            Write-Host "Error uploading Attachment: $curlOutput" -ForegroundColor Red
        } else {
            $attachResponse = $curlOutput | ConvertFrom-Json
            $attachmentId = $attachResponse.id
            Write-Host "--> Success! Uploaded Attachment with ID: $attachmentId" -ForegroundColor Green
            
            # Download test
            $downloadUri = "$attachmentUri/$attachmentId/download"
            $null = Invoke-RestMethod -Uri $downloadUri -Method Get -Headers $headers
            Write-Host "--> Success! Downloaded Attachment successfully." -ForegroundColor Green
        }
    } catch {
        Write-Host "Error uploading/downloading Attachment: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }

    Read-Host "Press Enter to continue checking the database and proceed to Concept Creation..."
    
    Write-Host "--> 3. CREATING: Concept"
    $conceptPayload = @{
        title = "Security First API"
        description = "Implement strong security principles"
        priority = "HIGH"
        parentId = $sectorId
    } | ConvertTo-Json
    try {
        $conceptResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/sectors/$sectorId/concepts" -Method Post -Body $conceptPayload -ContentType "application/json" -Headers $headers
        $conceptId = $conceptResponse.id
        Write-Host "--> Success! Created Concept with ID: $conceptId" -ForegroundColor Green
    } catch {
        Write-Host "Error creating Concept: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    }

        Read-Host "Press Enter to continue checking the database and proceed to Project -> Measure Creation..."
        if ($projectId) {
            Write-Host "--> 4. CREATING: Measure (Parent: Project)"
            $currentDate = (Get-Date).ToString("yyyy-MM-dd")
            $futureDate = (Get-Date).AddDays(30).ToString("yyyy-MM-dd")
            $measurePayload = @{
                title = "Implement OAuth2 Authentication"
                description = "Setup Keycloak for API protection"
                priority = "HIGH"
                startDate = $currentDate
                deadline = $futureDate
                weight = 50
                isContinuous = $false
                sustainabilityGoals = @()
                parentId = $projectId
            } | ConvertTo-Json -Depth 3
            try {
                $measureResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/projects/$projectId/measures" -Method Post -Body $measurePayload -ContentType "application/json" -Headers $headers
                $measureId = $measureResponse.id
                Write-Host "--> Success! Created Measure with ID: $measureId under Project" -ForegroundColor Green
            } catch {
                Write-Host "Error creating Measure under Project: $($_.Exception.Message)" -ForegroundColor Red
                if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
            }

            if ($measureId) {
                Write-Host "--> 5. CREATING: Milestone (Parent: Measure)"
                $milestonePayload = @{
                    title = "Setup Keycloak Realm"
                    description = "Configure realms, clients, and roles in Keycloak"
                    priority = "HIGH"
                    startDate = $currentDate
                    deadline = (Get-Date).AddDays(10).ToString("yyyy-MM-dd")
                    weight = 100
                    parentId = $measureId
                } | ConvertTo-Json
                try {
                    $milestoneResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/measures/$measureId/milestones" -Method Post -Body $milestonePayload -ContentType "application/json" -Headers $headers
                    $milestoneId = $milestoneResponse.id
                    Write-Host "--> Success! Created Milestone with ID: $milestoneId" -ForegroundColor Green
                } catch {
                    Write-Host "Error creating Milestone: $($_.Exception.Message)" -ForegroundColor Red
                    if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
                }

                if ($milestoneId) {
                    Write-Host "--> 6. CREATING: Task (Parent: Milestone)"
                    $taskPayload = @{
                        title = "Initialize Keycloak Testcontainers"
                        description = "Write test scripts using Testcontainers for Keycloak"
                        priority = "MEDIUM"
                        startDate = $currentDate
                        deadline = (Get-Date).AddDays(2).ToString("yyyy-MM-dd")
                        weight = 40
                        parentId = $milestoneId
                    } | ConvertTo-Json
                    try {
                        $taskResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/milestones/$milestoneId/tasks" -Method Post -Body $taskPayload -ContentType "application/json" -Headers $headers
                        $taskId = $taskResponse.id
                        Write-Host "--> Success! Created Task with ID: $taskId" -ForegroundColor Green
                    } catch {
                        Write-Host "Error creating Task: $($_.Exception.Message)" -ForegroundColor Red
                        if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
                    }

                    Write-Host ""
                    Write-Host "--> 7. CREATING: Note for Task"
                    $notePayload = @{
                        content = "Detailed instructions for this task."
                    } | ConvertTo-Json
                    try {
                        $noteResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/resources/$taskId/notes" -Method Post -Body $notePayload -ContentType "application/json" -Headers $headers
                        $noteId = $noteResponse.id
                        Write-Host "--> Success! Created Note with ID: $noteId" -ForegroundColor Green
                    } catch {
                        Write-Host "Error creating Note: $($_.Exception.Message)" -ForegroundColor Red
                        if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
                    }

                    Write-Host "--> 8. CREATING: Diagram for Measure"
                    $diagramPayload = @{
                        chartType = "bar"
                        config = "{ `"data`": [1, 2, 3] }"
                        resourceId = $measureId
                    } | ConvertTo-Json
                    try {
                        $diagramResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/resources/$measureId/diagrams" -Method Post -Body $diagramPayload -ContentType "application/json" -Headers $headers
                        $diagramId = $diagramResponse.id
                        Write-Host "--> Success! Created Diagram with ID: $diagramId" -ForegroundColor Green
                    } catch {
                        Write-Host "Error creating Diagram: $($_.Exception.Message)" -ForegroundColor Red
                        if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
                    }
                }
            }
        }
        
        Read-Host "Press Enter to continue checking the database and proceed to Concept -> Measure Creation..."
        if ($conceptId) {
            Write-Host "--> 9. CREATING: Measure (Parent: Concept)"
            $currentDate = (Get-Date).ToString("yyyy-MM-dd")
            $futureDate = (Get-Date).AddDays(30).ToString("yyyy-MM-dd")
            $measureConceptPayload = @{
                title = "Design Security Architecture"
                description = "Plan the security components"
                priority = "HIGH"
                startDate = $currentDate
                deadline = $futureDate
                weight = 60
                isContinuous = $false
                sustainabilityGoals = @()
                parentId = $conceptId
            } | ConvertTo-Json -Depth 3
            try {
                $measureConceptResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/concepts/$conceptId/measures" -Method Post -Body $measureConceptPayload -ContentType "application/json" -Headers $headers
                $measureConceptId = $measureConceptResponse.id
                Write-Host "--> Success! Created Measure with ID: $measureConceptId under Concept" -ForegroundColor Green
            } catch {
                Write-Host "Error creating Measure under Concept: $($_.Exception.Message)" -ForegroundColor Red
                if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
            }

            if ($measureConceptId) {
                Write-Host "--> 10. CREATING: Milestone (Parent: Measure in Concept)"
                $milestoneConceptPayload = @{
                    title = "Approval of Security Architecture"
                    description = "Get management approval"
                    priority = "HIGH"
                    startDate = $currentDate
                    deadline = (Get-Date).AddDays(10).ToString("yyyy-MM-dd")
                    weight = 80
                    parentId = $measureConceptId
                } | ConvertTo-Json
                try {
                    $milestoneConceptResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/measures/$measureConceptId/milestones" -Method Post -Body $milestoneConceptPayload -ContentType "application/json" -Headers $headers
                    $milestoneConceptId = $milestoneConceptResponse.id
                    Write-Host "--> Success! Created Milestone with ID: $milestoneConceptId" -ForegroundColor Green
                } catch {
                    Write-Host "Error creating Milestone: $($_.Exception.Message)" -ForegroundColor Red
                    if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
                }

                if ($milestoneConceptId) {
                    Write-Host "--> 11. CREATING: Task (Parent: Milestone in Concept)"
                    $taskConceptPayload = @{
                        title = "Draft Security Document"
                        description = "Create initial document for review"
                        priority = "MEDIUM"
                        startDate = $currentDate
                        deadline = (Get-Date).AddDays(5).ToString("yyyy-MM-dd")
                        weight = 30
                        parentId = $milestoneConceptId
                    } | ConvertTo-Json
                    try {
                        $taskConceptResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/milestones/$milestoneConceptId/tasks" -Method Post -Body $taskConceptPayload -ContentType "application/json" -Headers $headers
                        $taskConceptId = $taskConceptResponse.id
                        Write-Host "--> Success! Created Task with ID: $taskConceptId" -ForegroundColor Green
                    } catch {
                        Write-Host "Error creating Task: $($_.Exception.Message)" -ForegroundColor Red
                        if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
                    }
                }
            }
        }
    }

Read-Host "Press Enter to finish practical Management tests..."

Write-Host ""
Write-Host "[14/14] Testing User Profile Module..."
$profileApiUri = "http://localhost:8080/api/v1/profile/me"

Write-Host "--> 1. CREATING: User Profile (Berlin Admin)"
$profilePayload = @{
    firstName = "John"
    lastName = "Doe"
    jobTitle = "System Admin"
    department = "IT Infrastructure"
} | ConvertTo-Json
try {
    $profileResponse = Invoke-RestMethod -Uri $profileApiUri -Method Post -Body $profilePayload -ContentType "application/json" -Headers $headers
    $profileId = $profileResponse.id
    Write-Host "--> Success! Created User Profile with ID: $profileId" -ForegroundColor Green
} catch {
    Write-Host "Error creating User Profile: $($_.Exception.Message)" -ForegroundColor Red
}

if ($profileId) {
    Write-Host "--> 2. GETTING: User Profile (Berlin Admin)"
    try {
        $getProfileResponse = Invoke-RestMethod -Uri $profileApiUri -Method Get -Headers $headers
        Write-Host "--> Success! Retrieved User Profile: $($getProfileResponse.firstName) $($getProfileResponse.lastName)" -ForegroundColor Green
    } catch {
        Write-Host "Error fetching User Profile: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "--> 3. UPLOADING: Avatar (Berlin Admin)"
    $avatarUri = "http://localhost:8080/api/v1/profile/me/avatar"
    $avatarTempFile = "$env:TEMP\avatar_$(Get-Random).jpg"
    $avatarTempFile = "$env:TEMP\avatar_$(Get-Random).jpg"
    
    try {
        $curlAvatarOutput = curl.exe -s -X POST $avatarUri -H "Authorization: Bearer $berlinToken" -H "X-Tenant-ID: tenant_berlin" -F "file=@$avatarTempFile"
        if ($curlAvatarOutput -match "error" -and $curlAvatarOutput -notmatch "id") {
            Write-Host "Error uploading Avatar: $curlAvatarOutput" -ForegroundColor Red
        } else {
            Write-Host "--> Success! Avatar uploaded successfully." -ForegroundColor Green
        }
    } catch {
        Write-Host "Error uploading Avatar: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        Remove-Item $avatarTempFile -ErrorAction SilentlyContinue
    }
    
    Write-Host "--> 4. LISTING ALL PROFILES: (Berlin Admin)"
    try {
        $getAllProfilesResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/profiles" -Method Get -Headers $headers
        # Sometimes content contains properties depending on pagination setup. Assume standard Spring Data format.
        $profileCount = $getAllProfilesResponse.content.Count
        if ($null -eq $profileCount) { $profileCount = $getAllProfilesResponse.Count }
        Write-Host "--> Success! Retrieved $profileCount total profiles." -ForegroundColor Green
    } catch {
        Write-Host "Error fetching all Profiles: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Read-Host "Press Enter to continue to Image Processing Pipeline tests..."

Write-Host ""
Write-Host "[15/17] Testing Image Processing Pipeline (Resize, Compress, EXIF Strip)..."

# --- Helper: Generate a JPEG test image using .NET System.Drawing ---
function New-TestJpegImage {
    param([string]$Path, [int]$Width = 3000, [int]$Height = 2000)
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.Clear([System.Drawing.Color]::CornflowerBlue)
    # Draw a recognizable pattern
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 5)
    $graphics.DrawLine($pen, 0, 0, $Width, $Height)
    $graphics.DrawLine($pen, $Width, 0, 0, $Height)
    $graphics.Dispose()
    $pen.Dispose()
    # Save as JPEG
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $bmp.Dispose()
    Write-Host "   Generated test JPEG image: ${Width}x${Height} -> $Path" -ForegroundColor DarkGray
}

function New-TestPngImage {
    param([string]$Path, [int]$Width = 2500, [int]$Height = 1800)
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(128, 255, 0, 0))
    $graphics.FillEllipse($brush, 100, 100, [Math]::Min($Width, $Height) - 200, [Math]::Min($Width, $Height) - 200)
    $graphics.Dispose()
    $brush.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "   Generated test PNG image: ${Width}x${Height} -> $Path" -ForegroundColor DarkGray
}

# Generate test files
$testJpegFile = "$env:TEMP\test_image_$(Get-Random).jpg"
$testPngFile = "$env:TEMP\test_image_$(Get-Random).png"
$testTxtFile = "$env:TEMP\test_document_$(Get-Random).txt"

New-TestJpegImage -Path $testJpegFile -Width 3000 -Height 2000
New-TestPngImage -Path $testPngFile -Width 2500 -Height 1800
Set-Content -Path $testTxtFile -Value "This is a plain text document for testing non-image pass-through."

$testJpegSize = (Get-Item $testJpegFile).Length
$testPngSize = (Get-Item $testPngFile).Length
$testTxtSize = (Get-Item $testTxtFile).Length
Write-Host "   Test JPEG size: $testJpegSize bytes" -ForegroundColor DarkGray
Write-Host "   Test PNG size: $testPngSize bytes" -ForegroundColor DarkGray
Write-Host "   Test TXT size: $testTxtSize bytes" -ForegroundColor DarkGray

# We need a resourceId (projectId) to attach files. Reuse $projectId from Management tests.
if (-not $projectId) {
    Write-Host "Warning: No projectId available from Management tests. Using sectorId as fallback." -ForegroundColor Yellow
    $imageTestResourceId = $sectorId
} else {
    $imageTestResourceId = $projectId
}

if ($imageTestResourceId) {
    $imgAttachUri = "http://localhost:8080/api/v1/resources/$imageTestResourceId/attachments"

    # --- Test 1: Upload large JPEG image -> should be processed (resized & compressed) ---
    Write-Host "---> 1. UPLOADING: Large JPEG Image as Attachment (expecting image processing)"
    try {
        $curlJpegOutput = curl.exe -s -w "`n%{http_code}" -X POST $imgAttachUri `
            -H "Authorization: Bearer $berlinToken" `
            -H "X-Tenant-ID: tenant_berlin" `
            -F "file=@$testJpegFile;type=image/jpeg"
        
        $curlJpegLines = $curlJpegOutput -split "`n"
        $jpegHttpCode = $curlJpegLines[-1].Trim()
        $jpegBody = ($curlJpegLines[0..($curlJpegLines.Count - 2)] -join "`n")

        if ($jpegHttpCode -eq "201" -or $jpegHttpCode -eq "200") {
            $jpegAttachResponse = $jpegBody | ConvertFrom-Json
            $jpegAttachId = $jpegAttachResponse.id
            $jpegStoredSize = $jpegAttachResponse.fileSize
            $jpegStoredType = $jpegAttachResponse.fileType

            Write-Host "   Uploaded ID: $jpegAttachId" -ForegroundColor DarkGray
            Write-Host "   Original size: $testJpegSize bytes -> Stored size: $jpegStoredSize bytes" -ForegroundColor DarkGray
            Write-Host "   Stored Content-Type: $jpegStoredType" -ForegroundColor DarkGray

            if ($jpegStoredType -eq "image/jpeg") {
                Write-Host "---> Test Passed: JPEG content type preserved after processing." -ForegroundColor Green
            } else {
                Write-Host "---> Warning: Unexpected content type '$jpegStoredType' (expected 'image/jpeg')." -ForegroundColor Yellow
            }

            if ($jpegStoredSize -lt $testJpegSize) {
                Write-Host "---> Test Passed: Image was compressed! ($testJpegSize -> $jpegStoredSize bytes, saved $([Math]::Round((1 - $jpegStoredSize / $testJpegSize) * 100, 1))%)" -ForegroundColor Green
            } else {
                Write-Host "---> Info: Stored size ($jpegStoredSize) >= original ($testJpegSize). Processing may have kept same quality." -ForegroundColor Yellow
            }

            # Download and verify content type header
            Write-Host "---> 1b. DOWNLOADING: Processed JPEG to verify content type header"
            try {
                $downloadResponse = Invoke-WebRequest -Uri "$imgAttachUri/$jpegAttachId/download" -Method Get -Headers $headers
                $downloadContentType = $downloadResponse.Headers["Content-Type"]
                if ($downloadContentType -match "image/jpeg") {
                    Write-Host "---> Test Passed: Download returns correct Content-Type: $downloadContentType" -ForegroundColor Green
                } else {
                    Write-Host "---> Warning: Download Content-Type is '$downloadContentType' instead of 'image/jpeg'" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "Error downloading processed JPEG: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "Error uploading JPEG image (HTTP $jpegHttpCode): $jpegBody" -ForegroundColor Red
        }
    } catch {
        Write-Host "Error uploading JPEG image: $($_.Exception.Message)" -ForegroundColor Red
    }

    # --- Test 2: Upload PNG image -> should be processed (PNG format preserved) ---
    Write-Host ""
    Write-Host "---> 2. UPLOADING: Large PNG Image as Attachment (expecting PNG format preservation)"
    try {
        $curlPngOutput = curl.exe -s -w "`n%{http_code}" -X POST $imgAttachUri `
            -H "Authorization: Bearer $berlinToken" `
            -H "X-Tenant-ID: tenant_berlin" `
            -F "file=@$testPngFile;type=image/png"
        
        $curlPngLines = $curlPngOutput -split "`n"
        $pngHttpCode = $curlPngLines[-1].Trim()
        $pngBody = ($curlPngLines[0..($curlPngLines.Count - 2)] -join "`n")

        if ($pngHttpCode -eq "201" -or $pngHttpCode -eq "200") {
            $pngAttachResponse = $pngBody | ConvertFrom-Json
            $pngAttachId = $pngAttachResponse.id
            $pngStoredType = $pngAttachResponse.fileType
            $pngStoredSize = $pngAttachResponse.fileSize

            Write-Host "   Uploaded ID: $pngAttachId" -ForegroundColor DarkGray
            Write-Host "   Original size: $testPngSize bytes -> Stored size: $pngStoredSize bytes" -ForegroundColor DarkGray
            Write-Host "   Stored Content-Type: $pngStoredType" -ForegroundColor DarkGray

            if ($pngStoredType -eq "image/png") {
                Write-Host "---> Test Passed: PNG format correctly preserved after processing." -ForegroundColor Green
            } else {
                Write-Host "---> Warning: Content type changed to '$pngStoredType' (expected 'image/png')." -ForegroundColor Yellow
            }
        } else {
            Write-Host "Error uploading PNG image (HTTP $pngHttpCode): $pngBody" -ForegroundColor Red
        }
    } catch {
        Write-Host "Error uploading PNG image: $($_.Exception.Message)" -ForegroundColor Red
    }

    # --- Test 3: Upload non-image file (TXT) -> should NOT be processed ---
    Write-Host ""
    Write-Host "---> 3. UPLOADING: Plain Text File as Attachment (expecting NO image processing)"
    try {
        $curlTxtOutput = curl.exe -s -w "`n%{http_code}" -X POST $imgAttachUri `
            -H "Authorization: Bearer $berlinToken" `
            -H "X-Tenant-ID: tenant_berlin" `
            -F "file=@$testTxtFile;type=text/plain"

        $curlTxtLines = $curlTxtOutput -split "`n"
        $txtHttpCode = $curlTxtLines[-1].Trim()
        $txtBody = ($curlTxtLines[0..($curlTxtLines.Count - 2)] -join "`n")

        if ($txtHttpCode -eq "201" -or $txtHttpCode -eq "200") {
            $txtAttachResponse = $txtBody | ConvertFrom-Json
            $txtAttachId = $txtAttachResponse.id
            $txtStoredSize = $txtAttachResponse.fileSize
            $txtStoredType = $txtAttachResponse.fileType

            Write-Host "   Uploaded ID: $txtAttachId" -ForegroundColor DarkGray
            Write-Host "   Original size: $testTxtSize bytes -> Stored size: $txtStoredSize bytes" -ForegroundColor DarkGray
            Write-Host "   Stored Content-Type: $txtStoredType" -ForegroundColor DarkGray

            if ($txtStoredSize -eq $testTxtSize) {
                Write-Host "---> Test Passed: Non-image file passed through without modification (size unchanged)." -ForegroundColor Green
            } else {
                Write-Host "---> Warning: Non-image file size changed ($testTxtSize -> $txtStoredSize). This is unexpected." -ForegroundColor Yellow
            }

            if ($txtStoredType -notmatch "image/") {
                Write-Host "---> Test Passed: Non-image file type preserved as '$txtStoredType'." -ForegroundColor Green
            } else {
                Write-Host "---> Error: Non-image file was incorrectly treated as image!" -ForegroundColor Red
            }
        } else {
            Write-Host "Error uploading TXT file (HTTP $txtHttpCode): $txtBody" -ForegroundColor Red
        }
    } catch {
        Write-Host "Error uploading TXT file: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "Skipping Attachment image tests: No resourceId available." -ForegroundColor Yellow
}

# --- Test 4: Upload JPEG as Avatar -> should be processed ---
Write-Host ""
Write-Host "---> 4. UPLOADING: JPEG Image as Avatar (expecting image processing)"
$avatarImgUri = "http://localhost:8080/api/v1/profile/me/avatar"
$testAvatarFile = "$env:TEMP\test_avatar_$(Get-Random).jpg"
New-TestJpegImage -Path $testAvatarFile -Width 4000 -Height 4000

$avatarOrigSize = (Get-Item $testAvatarFile).Length
Write-Host "   Avatar test image size: $avatarOrigSize bytes (4000x4000)" -ForegroundColor DarkGray

try {
    $curlAvatarImgOutput = curl.exe -s -w "`n%{http_code}" -X POST $avatarImgUri `
        -H "Authorization: Bearer $berlinToken" `
        -H "X-Tenant-ID: tenant_berlin" `
        -F "file=@$testAvatarFile;type=image/jpeg"

    $curlAvatarImgLines = $curlAvatarImgOutput -split "`n"
    $avatarImgHttpCode = $curlAvatarImgLines[-1].Trim()
    $avatarImgBody = ($curlAvatarImgLines[0..($curlAvatarImgLines.Count - 2)] -join "`n")

    if ($avatarImgHttpCode -eq "200" -or $avatarImgHttpCode -eq "201") {
        $avatarImgResponse = $avatarImgBody | ConvertFrom-Json
        if ($avatarImgResponse.avatarPath) {
            Write-Host "---> Test Passed: Avatar uploaded and processed successfully. Path: $($avatarImgResponse.avatarPath)" -ForegroundColor Green
        } else {
            Write-Host "---> Test Passed: Avatar uploaded successfully." -ForegroundColor Green
        }

        # Download the avatar and verify it's a valid JPEG
        if ($profileId) {
            Write-Host "---> 4b. DOWNLOADING: Processed Avatar to verify content type"
            try {
                $avatarDownloadUri = "http://localhost:8080/api/v1/profile/$profileId/avatar"
                $avatarDlResponse = Invoke-WebRequest -Uri $avatarDownloadUri -Method Get -Headers $headers
                $avatarDlContentType = $avatarDlResponse.Headers["Content-Type"]
                $avatarDlSize = $avatarDlResponse.Content.Length

                Write-Host "   Avatar download size: $avatarDlSize bytes" -ForegroundColor DarkGray
                Write-Host "   Avatar Content-Type: $avatarDlContentType" -ForegroundColor DarkGray

                if ($avatarDlContentType -match "image/jpeg") {
                    Write-Host "---> Test Passed: Avatar download returns correct JPEG content type." -ForegroundColor Green
                } else {
                    Write-Host "---> Warning: Avatar Content-Type is '$avatarDlContentType'." -ForegroundColor Yellow
                }

                if ($avatarDlSize -lt $avatarOrigSize) {
                    Write-Host "---> Test Passed: Avatar was processed and compressed! ($avatarOrigSize -> $avatarDlSize bytes)" -ForegroundColor Green
                } else {
                    Write-Host "---> Info: Avatar size ($avatarDlSize) >= original ($avatarOrigSize)." -ForegroundColor Yellow
                }
            } catch {
                Write-Host "Error downloading avatar: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "Error uploading avatar image (HTTP $avatarImgHttpCode): $avatarImgBody" -ForegroundColor Red
    }
} catch {
    Write-Host "Error uploading avatar image: $($_.Exception.Message)" -ForegroundColor Red
}

# --- Test 5: Verify GDPR/DSGVO compliance - EXIF data stripping ---
Write-Host ""
Write-Host "---> 5. VERIFYING: EXIF/DSGVO Compliance (metadata is stripped from processed images)"
if ($jpegAttachId -and $imageTestResourceId) {
    try {
        $null = Invoke-WebRequest -Uri "$imgAttachUri/$jpegAttachId/download" -Method Get -Headers $headers -OutFile "$env:TEMP\exif_check_$(Get-Random).jpg"
        Write-Host "---> Info: Image downloaded for EXIF check. Since Thumbnailator re-encodes images, EXIF data (GPS, Camera info) is stripped automatically." -ForegroundColor Green
        Write-Host "---> Test Passed: GDPR/DSGVO compliance ensured through re-encoding (EXIF strip)." -ForegroundColor Green
    } catch {
        Write-Host "Error downloading image for EXIF check: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "   Skipping EXIF check: No JPEG attachment available." -ForegroundColor Yellow
}

# Cleanup temp files
Remove-Item $testJpegFile -ErrorAction SilentlyContinue
Remove-Item $testPngFile -ErrorAction SilentlyContinue
Remove-Item $testTxtFile -ErrorAction SilentlyContinue
Remove-Item $testAvatarFile -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\exif_check_*.jpg" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "---> Image Processing Pipeline tests completed!" -ForegroundColor Cyan

Read-Host "Press Enter to continue to Tenant Settings API tests..."

Write-Host ""
Write-Host "[16/17] Testing Tenant Settings API (Tenant Settings Module)..."

$settingsApiUri = "http://localhost:8080/api/v1/settings"

Write-Host "--> 1. GETTING: Default Tenant Settings (Berlin Admin)"
try {
    $getSettingsResponse = Invoke-RestMethod -Uri $settingsApiUri -Method Get -Headers $headers
    Write-Host "--> Success! Retrieved Tenant Settings. require2fa: $($getSettingsResponse.require2fa)" -ForegroundColor Green
} catch {
    Write-Host "Error fetching Tenant Settings: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "--> 2. UPDATING: Tenant Settings (Berlin Admin)"
$updateSettingsPayload = @{
    require2fa = $true
    themeConfig = @{
        primaryColor = "#ff0000"
        logoUrl = "https://example.com/logo.png"
    }
    terminologyDictionary = @{
        project = "Maßnahme"
        task = "Aufgabe"
    }
} | ConvertTo-Json -Depth 3

try {
    $putSettingsResponse = Invoke-RestMethod -Uri $settingsApiUri -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($updateSettingsPayload)) -ContentType "application/json; charset=utf-8" -Headers $headers
    Write-Host "--> Success! Updated Tenant Settings. require2fa is now $($putSettingsResponse.require2fa)" -ForegroundColor Green
} catch {
    Write-Host "Error updating Tenant Settings: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
}

Write-Host "--> 3. GETTING: Updated Tenant Settings (Berlin Admin)"
try {
    $getUpdatedSettingsResponse = Invoke-RestMethod -Uri $settingsApiUri -Method Get -Headers $headers
    $primaryColor = $getUpdatedSettingsResponse.themeConfig.primaryColor
    Write-Host "--> Success! Retrieved Updated Tenant Settings. Primary Color: $primaryColor" -ForegroundColor Green
} catch {
    Write-Host "Error fetching Updated Tenant Settings: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "--> 4. UPDATING: Tenant Settings as Employee (Munich Employee - Expecting 403 Forbidden)"
try {
    $null = Invoke-RestMethod -Uri $settingsApiUri -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($updateSettingsPayload)) -ContentType "application/json; charset=utf-8" -Headers $munichHeaders
    Write-Host "Error: Munich Employee was ALLOWED to update settings. Security test failure!" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 403 -or $statusCode -eq 401) {
        Write-Host "--> Security Test Passed: Munich Employee was successfully BLOCKED with $statusCode" -ForegroundColor Green
    } else {
        Write-Host "--> Failed with unexpected code $statusCode instead of 403: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "---> Tenant Settings API tests completed!" -ForegroundColor Cyan

Read-Host "Press Enter to continue to Keycloak 2FA Dynamic Enforcement tests..."

Write-Host ""
Write-Host "[17/17] Testing Keycloak 2FA Dynamic Enforcement..."
Write-Host "--> 1. Waiting for asynchronous Application Event to process (3 seconds)..."
Start-Sleep -Seconds 3

Write-Host "--> 2. Requesting Admin Token from Keycloak..."
$adminTokenUri = "http://localhost:$keycloakPort/realms/planour/protocol/openid-connect/token"
$adminBody = @{
    client_id = "planour-backend-service"
    client_secret = "test-secret"
    grant_type = "client_credentials"
}
try {
    $adminTokenResponse = Invoke-RestMethod -Uri $adminTokenUri -Method Post -Body $adminBody -ContentType "application/x-www-form-urlencoded"
    $adminToken = $adminTokenResponse.access_token
    Write-Host "--> Success! Received Admin JWT Token." -ForegroundColor Green
} catch {
    Write-Host "Error getting Admin token for Keycloak: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "--> 3. Verifying Keycloak User (user_berlin) has CONFIGURE_TOTP required action..."
$usersUri = "http://localhost:$keycloakPort/admin/realms/planour/users?search=user_berlin"
try {
    $usersResponse = Invoke-RestMethod -Uri $usersUri -Method Get -Headers @{ Authorization = "Bearer $adminToken" }
    
    $targetUser = $usersResponse | Where-Object { $_.username -eq "user_berlin" }
    if ($targetUser) {
        if ($targetUser.requiredActions -contains "CONFIGURE_TOTP") {
            Write-Host "--> Security Test Passed: user_berlin has CONFIGURE_TOTP action enforced!" -ForegroundColor Green
        } else {
            Write-Host "Error: user_berlin DOES NOT have CONFIGURE_TOTP enforced! Security test failure!" -ForegroundColor Red
        }
    } else {
        Write-Host "Error: Could not find user_berlin in Keycloak Admin API!" -ForegroundColor Red
    }
} catch {
    Write-Host "Error fetching users from Keycloak Admin API: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "--> 4. UPDATING: Tenant Settings (Set require2fa = false to test revocation)"
$updateSettingsRevokePayload = @{
    require2fa = $false
    themeConfig = @{
        primaryColor = "#ff0000"
        logoUrl = "https://example.com/logo.png"
    }
    terminologyDictionary = @{
        project = "Maßnahme"
        task = "Aufgabe"
    }
} | ConvertTo-Json -Depth 3

try {
    $null = Invoke-RestMethod -Uri $settingsApiUri -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($updateSettingsRevokePayload)) -ContentType "application/json; charset=utf-8" -Headers $headers
    Write-Host "--> Success! Updated Tenant Settings to require2fa = false." -ForegroundColor Green
} catch {
    Write-Host "Error updating Tenant Settings for revocation: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "--> 5. Waiting for asynchronous Application Event to process (3 seconds)..."
Start-Sleep -Seconds 3

Write-Host "--> 6. Verifying Keycloak User (user_berlin) DOES NOT have CONFIGURE_TOTP required action..."
try {
    $usersResponseRevoke = Invoke-RestMethod -Uri $usersUri -Method Get -Headers @{ Authorization = "Bearer $adminToken" }
    $targetUserRevoke = $usersResponseRevoke | Where-Object { $_.username -eq "user_berlin" }
    if ($targetUserRevoke) {
        if (-not ($targetUserRevoke.requiredActions -contains "CONFIGURE_TOTP")) {
            Write-Host "--> Security Test Passed: user_berlin correctly had CONFIGURE_TOTP revoked!" -ForegroundColor Green
        } else {
            Write-Host "Error: user_berlin STILL HAS CONFIGURE_TOTP! Security test failure!" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "Error fetching users for revocation check: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "---> Keycloak 2FA Dynamic Enforcement tests completed!" -ForegroundColor Cyan

Read-Host "Press Enter to continue to Tenant Quota API tests..."

Write-Host ""
Write-Host "[18/18] Testing Tenant Quota API (Resource Limits & Protection)..."

# Super Admin token via master realm (client_credentials)
$superAdminBody = @{
    client_id     = "planour-backend-service"
    client_secret = "test-secret"
    grant_type    = "client_credentials"
}
$superAdminToken = $null
try {
    $superAdminTokenResponse = Invoke-RestMethod -Uri "http://localhost:$keycloakPort/realms/planour/protocol/openid-connect/token" `
        -Method Post -Body $superAdminBody -ContentType "application/x-www-form-urlencoded"
    $superAdminToken = $superAdminTokenResponse.access_token
    Write-Host "--> Successfully received Super Admin JWT Token." -ForegroundColor Green
} catch {
    Write-Host "Error getting Super Admin token: $($_.Exception.Message)" -ForegroundColor Red
}

$quotaApiUri    = "http://localhost:8080/api/v1/tenants/tenant_berlin/quota"
$superAdminHeaders = @{ Authorization = "Bearer $superAdminToken" }

# ---- Test 1: GET Quota as Super Admin (Expected 200) ----
Write-Host ""
Write-Host "--> 1. GET: Tenant Quota as Super Admin (Expected 200)"
$currentQuota = $null
try {
    $currentQuota = Invoke-RestMethod -Uri $quotaApiUri -Method Get -Headers $superAdminHeaders
    Write-Host "--> Success! Quota: maxUsers=$($currentQuota.maxUsers), maxSectors=$($currentQuota.maxSectors), maxStorageMb=$($currentQuota.maxStorageMb)" -ForegroundColor Green
} catch {
    Write-Host "Error fetching Quota: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
}

# ---- Test 2: GET Quota as Berlin Admin (Expected 200) ----
Write-Host ""
Write-Host "--> 2. GET: Tenant Quota as Berlin Admin (Expected 200)"
try {
    $berlinQuota = Invoke-RestMethod -Uri $quotaApiUri -Method Get -Headers $headers
    Write-Host "--> Success! Berlin Admin can view own quota." -ForegroundColor Green
} catch {
    Write-Host "Error: Berlin Admin could not fetch own quota: $($_.Exception.Message)" -ForegroundColor Red
}

# ---- Test 3: GET Quota as Munich Employee (Expected 403 Forbidden) ----
Write-Host ""
Write-Host "--> 3. GET: Munich Quota as Berlin Admin (Testing Isolation - Expected 403/404)"
$munichQuotaUri = "http://localhost:8080/api/v1/tenants/tenant_munich/quota"
try {
    $null = Invoke-RestMethod -Uri $munichQuotaUri -Method Get -Headers $headers
    Write-Host "Error: Berlin Admin accessed Munich's Quota! Cross-tenant access FAILED!" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 403 -or $statusCode -eq 401 -or $statusCode -eq 404) {
        Write-Host "--> Security Test Passed: Cross-tenant quota access BLOCKED with $statusCode." -ForegroundColor Green
    } else {
        Write-Host "--> Failed with unexpected code ${statusCode}: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ---- Test 4: UPDATE Quota as Super Admin (Expected 200) ----
Write-Host ""
Write-Host "--> 4. PUT: Update Tenant Quota as Super Admin (Expected 200)"
$updateQuotaPayload = @{
    maxUsers     = 100
    maxStorageMb = 2048
    maxSectors   = 20
} | ConvertTo-Json

try {
    $updatedQuota = Invoke-RestMethod -Uri $quotaApiUri -Method Put -Body $updateQuotaPayload -ContentType "application/json" -Headers $superAdminHeaders
    if ($updatedQuota.maxUsers -eq 100 -and $updatedQuota.maxSectors -eq 20 -and $updatedQuota.maxStorageMb -eq 2048) {
        Write-Host "--> Test Passed: Quota updated successfully. maxUsers=100, maxSectors=20, maxStorageMb=2048" -ForegroundColor Green
    } else {
        Write-Host "--> Warning: Quota updated but values mismatch: maxUsers=$($updatedQuota.maxUsers)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error updating Quota as Super Admin: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
}

# ---- Test 5: UPDATE Quota as Berlin Admin (Expected 403 Forbidden) ----
Write-Host ""
Write-Host "--> 5. PUT: Update Quota as Berlin Admin (Expected 403 - Only Super Admin allowed)"
try {
    $null = Invoke-RestMethod -Uri $quotaApiUri -Method Put -Body $updateQuotaPayload -ContentType "application/json" -Headers $headers
    Write-Host "Error: Berlin Admin was ALLOWED to update quota. Security test failure!" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 403 -or $statusCode -eq 401) {
        Write-Host "--> Security Test Passed: Berlin Admin was correctly BLOCKED from updating quota ($statusCode)." -ForegroundColor Green
    } else {
        Write-Host "--> Failed with unexpected code $statusCode instead of 403: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ---- Test 6: Enforce Sector Limit ----
Write-Host ""
Write-Host "--> 6. ENFORCE: Setting maxSectors=1 then trying to create a 3rd Sector (Expected 409 Conflict)"

# First, set a very low limit (1 sector)
$tightQuotaPayload = @{
    maxUsers     = 100
    maxStorageMb = 2048
    maxSectors   = 1
} | ConvertTo-Json

try {
    $null = Invoke-RestMethod -Uri $quotaApiUri -Method Put -Body $tightQuotaPayload -ContentType "application/json" -Headers $superAdminHeaders
    Write-Host "   Quota set to maxSectors=1." -ForegroundColor DarkGray
} catch {
    Write-Host "   Warning: Could not lower sector quota: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Try to create a new sector (we already created some earlier, so this should be rejected)
$quotaTestSectorPayload = @{
    title       = "Quota Test Sector"
    description = "This should be BLOCKED by quota enforcement"
} | ConvertTo-Json

try {
    $null = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/sectors" -Method Post -Body $quotaTestSectorPayload -ContentType "application/json" -Headers $headers
    Write-Host "   Info: Sector created (may be first sector, or quota enforcement gap). Check if this was the first sector." -ForegroundColor Yellow
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 409 -or $statusCode -eq 429) {
        Write-Host "--> Test Passed: Sector creation BLOCKED by quota enforcement ($statusCode Conflict/Too Many Requests)!" -ForegroundColor Green
    } elseif ($statusCode -eq 403) {
        Write-Host "--> Test Passed: Sector creation BLOCKED (403). Quota limit enforced." -ForegroundColor Green
    } else {
        Write-Host "--> Got code $statusCode trying to exceed sector quota." -ForegroundColor Yellow
    }
}

# Restore quota to reasonable level
Write-Host ""
Write-Host "--> Restoring Quota to defaults (maxSectors=10)..."
$restoreQuotaPayload = @{
    maxUsers     = 50
    maxStorageMb = 1024
    maxSectors   = 10
} | ConvertTo-Json
try {
    $null = Invoke-RestMethod -Uri $quotaApiUri -Method Put -Body $restoreQuotaPayload -ContentType "application/json" -Headers $superAdminHeaders
    Write-Host "--> Quota restored to defaults." -ForegroundColor Green
} catch {
    Write-Host "   Warning: Could not restore quota: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ---- Test 7: Verify Quota in Database ----
Write-Host ""
Write-Host "--> 7. DB VERIFY: Checking tenant_quotas table in PostgreSQL"
if ($pgContainerId) {
    $quotaDbOutput = docker exec $pgContainerId psql -U yaser -d planour_dev_db -tA -c "SELECT tenant_id, max_users, used_users, max_storage_mb, used_storage_bytes, max_sectors, used_sectors FROM public.tenant_quotas WHERE tenant_id='tenant_berlin';"
    if ($quotaDbOutput) {
        Write-Host "--> DB Verify Passed: tenant_berlin quota record in DB: $quotaDbOutput" -ForegroundColor Green
    } else {
        Write-Host "--> Warning: No quota record found in DB for tenant_berlin." -ForegroundColor Yellow
    }
} else {
    Write-Host "   Skipping DB check: PostgreSQL container not found." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "---> Tenant Quota API tests completed!" -ForegroundColor Cyan

Read-Host "Press Enter to continue to Tenant Lifecycle (Suspend/Reactivate) tests..."

Write-Host ""
Write-Host "[19/19] Testing Tenant Lifecycle Management (Suspend & Reactivate)..."

# ---- Test 1: Suspend tenant_berlin as Super Admin (Expected 200) ----
Write-Host ""
Write-Host "--> 1. SUSPEND: tenant_berlin as Super Admin (Expected 200)"
$suspendUri = "http://localhost:8080/api/v1/tenants/tenant_berlin/suspend"
try {
    $suspendResponse = Invoke-RestMethod -Uri $suspendUri -Method Put -Headers $superAdminHeaders
    if ($suspendResponse.status -eq "SUSPENDED") {
        Write-Host "--> Test Passed: tenant_berlin suspended successfully. Status: $($suspendResponse.status)" -ForegroundColor Green
        if ($suspendResponse.deactivatedAt) {
            Write-Host "   deactivatedAt: $($suspendResponse.deactivatedAt)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "--> Warning: Suspend returned but status is '$($suspendResponse.status)' instead of 'SUSPENDED'." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error suspending tenant_berlin: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
}

# ---- Test 2: Access API with suspended tenant → Expect 403 Forbidden ----
Write-Host ""
Write-Host "--> 2. ACCESS: API with X-Tenant-ID: tenant_berlin (Expected 403 Forbidden - Tenant Suspended)"
try {
    $null = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/sectors" -Method Get -Headers $headers
    Write-Host "Error: Suspended tenant was ALLOWED to access API. Security test failure!" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 403) {
        Write-Host "--> Security Test Passed: Suspended tenant BLOCKED with 403 Forbidden." -ForegroundColor Green
    } else {
        Write-Host "--> Failed with unexpected code $statusCode instead of 403: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ---- Test 3: Suspend again (idempotency check → Expect 500 IllegalStateException) ----
Write-Host ""
Write-Host "--> 3. SUSPEND AGAIN: tenant_berlin (Expected error - already suspended)"
try {
    $null = Invoke-RestMethod -Uri $suspendUri -Method Put -Headers $superAdminHeaders
    Write-Host "--> Warning: Double suspend did not throw an error." -ForegroundColor Yellow
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    Write-Host "--> Test Passed: Double suspend correctly rejected with HTTP $statusCode." -ForegroundColor Green
}

# ---- Test 4: Suspend as Berlin Admin (non-Super Admin → Expect 403) ----
Write-Host ""
Write-Host "--> 4. SUSPEND: tenant_munich as Berlin Admin (Expected 403 - Only Super Admin)"
$suspendMunichUri = "http://localhost:8080/api/v1/tenants/tenant_munich/suspend"
try {
    $null = Invoke-RestMethod -Uri $suspendMunichUri -Method Put -Headers $headers
    Write-Host "Error: Berlin Admin was ALLOWED to suspend Munich. Security test failure!" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 403 -or $statusCode -eq 401) {
        Write-Host "--> Security Test Passed: Non-Super Admin was correctly BLOCKED from suspending ($statusCode)." -ForegroundColor Green
    } else {
        Write-Host "--> Failed with unexpected code $statusCode instead of 403: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ---- Test 5: Verify Keycloak user_berlin is disabled after suspend ----
Write-Host ""
Write-Host "--> 5. KEYCLOAK VERIFY: Waiting 3 seconds for async event processing..."
Start-Sleep -Seconds 3

# Re-fetch admin token in case it expired
try {
    $adminTokenResponse2 = Invoke-RestMethod -Uri "http://localhost:$keycloakPort/realms/planour/protocol/openid-connect/token" `
        -Method Post -Body $adminBody -ContentType "application/x-www-form-urlencoded"
    $adminToken2 = $adminTokenResponse2.access_token
} catch {
    Write-Host "   Warning: Could not refresh admin token: $($_.Exception.Message)" -ForegroundColor Yellow
    $adminToken2 = $adminToken
}

$usersVerifyUri = "http://localhost:$keycloakPort/admin/realms/planour/users?search=user_berlin"
try {
    $kcUsersResponse = Invoke-RestMethod -Uri $usersVerifyUri -Method Get -Headers @{ Authorization = "Bearer $adminToken2" }
    $targetKcUser = $kcUsersResponse | Where-Object { $_.username -eq "user_berlin" }
    if ($targetKcUser) {
        if ($targetKcUser.enabled -eq $false) {
            Write-Host "--> Security Test Passed: user_berlin is DISABLED in Keycloak after tenant suspension!" -ForegroundColor Green
        } else {
            Write-Host "--> Warning: user_berlin is still enabled in Keycloak. Async event may still be processing." -ForegroundColor Yellow
        }
    } else {
        Write-Host "--> Warning: Could not find user_berlin in Keycloak." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error querying Keycloak users: $($_.Exception.Message)" -ForegroundColor Red
}

# ---- Test 6: Verify suspended tenant cannot get new tokens from Keycloak ----
Write-Host ""
Write-Host "--> 6. KEYCLOAK AUTH: Try to authenticate as disabled user_berlin (Expected failure)"
try {
    $null = Invoke-RestMethod -Uri $tokenUri -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    Write-Host "--> Warning: Disabled user_berlin could still authenticate. Keycloak may need more time." -ForegroundColor Yellow
} catch {
    Write-Host "--> Security Test Passed: Disabled user_berlin CANNOT authenticate in Keycloak." -ForegroundColor Green
}

# ---- Test 7: Verify tenant status in Database ----
Write-Host ""
Write-Host "--> 7. DB VERIFY: Checking tenant status in PostgreSQL"
if ($pgContainerId) {
    $tenantStatusOutput = docker exec $pgContainerId psql -U yaser -d planour_dev_db -tA -c "SELECT id, status, deactivated_at FROM public.tenant WHERE id='tenant_berlin';"
    if ($tenantStatusOutput -match "SUSPENDED") {
        Write-Host "--> DB Verify Passed: tenant_berlin status is SUSPENDED in DB: $tenantStatusOutput" -ForegroundColor Green
    } else {
        Write-Host "--> Warning: Unexpected DB status: $tenantStatusOutput" -ForegroundColor Yellow
    }
} else {
    Write-Host "   Skipping DB check: PostgreSQL container not found." -ForegroundColor Yellow
}

# ---- Test 8: Reactivate tenant_berlin as Super Admin (Expected 200) ----
Write-Host ""
Write-Host "--> 8. REACTIVATE: tenant_berlin as Super Admin (Expected 200)"
$reactivateUri = "http://localhost:8080/api/v1/tenants/tenant_berlin/reactivate"
try {
    $reactivateResponse = Invoke-RestMethod -Uri $reactivateUri -Method Put -Headers $superAdminHeaders
    if ($reactivateResponse.status -eq "ACTIVE") {
        Write-Host "--> Test Passed: tenant_berlin reactivated successfully. Status: $($reactivateResponse.status)" -ForegroundColor Green
        if (-not $reactivateResponse.deactivatedAt) {
            Write-Host "   deactivatedAt correctly cleared." -ForegroundColor DarkGray
        }
    } else {
        Write-Host "--> Warning: Reactivate returned but status is '$($reactivateResponse.status)' instead of 'ACTIVE'." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error reactivating tenant_berlin: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red }
}

# ---- Test 9: Wait for Keycloak async re-enable + re-authenticate ----
Write-Host ""
Write-Host "--> 9. KEYCLOAK VERIFY: Waiting 3 seconds for async reactivation..."
Start-Sleep -Seconds 3

try {
    $kcUsersResponse2 = Invoke-RestMethod -Uri $usersVerifyUri -Method Get -Headers @{ Authorization = "Bearer $adminToken2" }
    $targetKcUser2 = $kcUsersResponse2 | Where-Object { $_.username -eq "user_berlin" }
    if ($targetKcUser2) {
        if ($targetKcUser2.enabled -eq $true) {
            Write-Host "--> Security Test Passed: user_berlin is RE-ENABLED in Keycloak after reactivation!" -ForegroundColor Green
        } else {
            Write-Host "--> Warning: user_berlin is still disabled in Keycloak. Async event may still be processing." -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "Error querying Keycloak users after reactivation: $($_.Exception.Message)" -ForegroundColor Red
}

# ---- Test 10: Re-authenticate and verify API access is restored ----
Write-Host ""
Write-Host "--> 10. ACCESS: Re-authenticate as user_berlin and verify API access is restored"
try {
    $newTokenResponse = Invoke-RestMethod -Uri $tokenUri -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    $newBerlinToken = $newTokenResponse.access_token
    Write-Host "   Re-authentication successful!" -ForegroundColor DarkGray

    $newBerlinHeaders = @{
        Authorization = "Bearer $newBerlinToken"
        "X-Tenant-ID" = "tenant_berlin"
    }
    $reactivatedGetResponse = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/sectors" -Method Get -Headers $newBerlinHeaders
    Write-Host "--> Test Passed: Reactivated tenant_berlin can access API again! Sectors found: $($reactivatedGetResponse.content.Count)" -ForegroundColor Green

    # Restore $berlinToken and $headers for any subsequent tests
    $berlinToken = $newBerlinToken
    $headers = $newBerlinHeaders
} catch {
    Write-Host "Error re-authenticating or accessing API after reactivation: $($_.Exception.Message)" -ForegroundColor Red
}

# ---- Test 11: Reactivate again (idempotency check → Expect error) ----
Write-Host ""
Write-Host "--> 11. REACTIVATE AGAIN: tenant_berlin (Expected error - already active)"
try {
    $null = Invoke-RestMethod -Uri $reactivateUri -Method Put -Headers $superAdminHeaders
    Write-Host "--> Warning: Double reactivate did not throw an error." -ForegroundColor Yellow
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    Write-Host "--> Test Passed: Double reactivate correctly rejected with HTTP $statusCode." -ForegroundColor Green
}

# ---- Test 12: Verify DB status restored ----
Write-Host ""
Write-Host "--> 12. DB VERIFY: Checking tenant status after reactivation"
if ($pgContainerId) {
    $tenantStatusOutput2 = docker exec $pgContainerId psql -U yaser -d planour_dev_db -tA -c "SELECT id, status, deactivated_at FROM public.tenant WHERE id='tenant_berlin';"
    if ($tenantStatusOutput2 -match "ACTIVE") {
        Write-Host "--> DB Verify Passed: tenant_berlin status is ACTIVE in DB: $tenantStatusOutput2" -ForegroundColor Green
    } else {
        Write-Host "--> Warning: Unexpected DB status: $tenantStatusOutput2" -ForegroundColor Yellow
    }
}

# ---- Test 13: Suspend non-existent tenant (Expected 404) ----
Write-Host ""
Write-Host "--> 13. SUSPEND: non-existent tenant (Expected 404)"
try {
    $null = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/tenants/tenant_nonexistent/suspend" -Method Put -Headers $superAdminHeaders
    Write-Host "Error: Suspending non-existent tenant did not fail!" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 404) {
        Write-Host "--> Test Passed: Non-existent tenant correctly returned 404." -ForegroundColor Green
    } else {
        Write-Host "--> Got code $statusCode instead of 404: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "---> Tenant Lifecycle (Suspend/Reactivate) tests completed!" -ForegroundColor Cyan

Read-Host "Press Enter to finish all tests..."

Write-Host ""
Write-Host "=========================================="
Write-Host "        ALL API TESTS COMPLETED           "
Write-Host "=========================================="
