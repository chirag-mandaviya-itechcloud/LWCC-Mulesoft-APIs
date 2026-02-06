# Mule Flow Design

## Salesforce PDF Split System API

This document describes the logical flow design for the MuleSoft implementation. No actual code (DataWeave, Java, Mule XML) is included per requirements.

---

## Table of Contents

1. [Application Structure](#application-structure)
2. [Main API Flow](#main-api-flow)
3. [Synchronous Split Flow](#synchronous-split-flow)
4. [Asynchronous Job Flow](#asynchronous-job-flow)
5. [Job Worker Flow](#job-worker-flow)
6. [Subflows](#subflows)
7. [Global Error Handler](#global-error-handler)
8. [Connector Configuration](#connector-configuration)

---

## Application Structure

```
src/main/mule/
├── sf-doc-split-api.xml              # Main API router (APIkit)
├── flows/
│   ├── split-sync-flow.xml           # Synchronous split implementation
│   ├── split-async-flow.xml          # Async job creation
│   ├── job-worker-flow.xml           # Background job processor
│   └── job-status-flow.xml           # Job status retrieval
├── subflows/
│   ├── generate-correlation-id.xml   # Correlation ID generation
│   ├── validate-input-params.xml     # Input validation
│   ├── salesforce-validation.xml     # SF existence checks
│   ├── check-idempotency.xml         # Idempotency lookup/store
│   ├── pdf-download.xml              # Stream PDF from SF
│   ├── pdf-split-planning.xml        # Analyze and plan split
│   ├── pdf-split-execution.xml       # Execute the split
│   ├── upload-part-to-sf.xml         # Upload single part
│   ├── cleanup-temp-files.xml        # Delete temp storage
│   └── cleanup-created-parts.xml     # Rollback on failure
├── error-handlers/
│   └── global-error-handler.xml      # Centralized error handling
└── global-config.xml                 # Global configurations
```

---

## Main API Flow

### Flow: sf-doc-split-api

**Purpose:** HTTP listener and APIkit router for all endpoints

```
┌─────────────────────────────────────────────────────────────────────┐
│  FLOW: sf-doc-split-api                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  [HTTP Listener]                                                    │
│    • Path: /sys/sf-doc-split/v1/*                                   │
│    • Port: ${http.port}                                             │
│    • Allowed Methods: POST, GET                                     │
│                                                                     │
│         │                                                           │
│         ▼                                                           │
│  [APIkit Router]                                                    │
│    • RAML: sf-doc-split-api.raml                                    │
│                                                                     │
│    Routes:                                                          │
│    ├── POST /claims/{claimId}/documents/{docId}/split               │
│    │   → split-sync-flow                                            │
│    │                                                                │
│    ├── POST /claims/{claimId}/documents/{docId}/split-jobs          │
│    │   → split-async-flow                                           │
│    │                                                                │
│    └── GET /split-jobs/{jobId}                                      │
│        → job-status-flow                                            │
│                                                                     │
│  [Error Handler Reference: global-error-handler]                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Synchronous Split Flow

### Flow: split-sync-flow

**Purpose:** Handle synchronous split requests including dry-run

```
┌─────────────────────────────────────────────────────────────────────┐
│  FLOW: split-sync-flow                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ STEP 1: Initialize Request Context                          │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  [Flow Reference: generate-correlation-id]                          │
│    • Extract from X-Correlation-Id header or generate UUID          │
│    • Store in variable: correlationId                               │
│                                                                     │
│  [Set Variables: Extract Parameters]                                │
│    • claimId ← attributes.uriParams.claimId                         │
│    • contentDocumentId ← attributes.uriParams.contentDocumentId     │
│    • maxPartSizeMb ← min(queryParam ?: 15, 15)                      │
│    • maxParts ← min(queryParam ?: 5, 5)                             │
│    • dryRun ← queryParam ?: false                                   │
│                                                                     │
│  [Logger: REQUEST_RECEIVED]                                         │
│    • Level: INFO                                                    │
│    • Data: {correlationId, claimId, contentDocumentId, dryRun}      │
│                                                                     │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ STEP 2: Validate Input                                      │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  [Flow Reference: validate-input-params]                            │
│    • Validate claimId format (15/18 char SF ID)                     │
│    • Validate contentDocumentId format (069...)                     │
│    • On failure: Raise VALIDATION_ERROR                             │
│                                                                     │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ STEP 3: Salesforce Validation                               │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  [Flow Reference: salesforce-validation-subflow]                    │
│    • Query: Verify claim exists                                     │
│    • Query: Verify document linked to claim                         │
│    • Query: Fetch ContentVersion metadata (latest)                  │
│    • Check: FileExtension = 'pdf'                                   │
│    • Store: contentVersionMetadata variable                         │
│                                                                     │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ STEP 4: Idempotency Check                                   │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  [Flow Reference: check-idempotency]                                │
│    • Compute key: SHA256(claimId|docId|versionId)                   │
│    • Query Object Store                                             │
│    • If COMPLETED → Return cached result (exit flow)                │
│    • If IN_PROGRESS → Return 409 Conflict (exit flow)               │
│    • If FAILED (non-retryable) → Return cached error (exit flow)    │
│    • Otherwise → Continue                                           │
│                                                                     │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ STEP 5: Download PDF                                        │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  [Flow Reference: pdf-download-subflow]                             │
│    • Create temp directory: {mule.home}/temp/pdf-split/{corrId}/    │
│    • HTTP GET: /sobjects/ContentVersion/{id}/VersionData            │
│    • Stream response to temp file: source.pdf                       │
│    • Store: tempFilePath variable                                   │
│                                                                     │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ STEP 6: Analyze and Plan Split                              │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  [Flow Reference: pdf-split-planning-subflow]                       │
│    • Java Component: Analyze PDF structure                          │
│      - Parse page count                                             │
│      - Calculate individual page sizes                              │
│      - Validate PDF integrity                                       │
│    • Java Component: Calculate split plan                           │
│      - Greedy page-boundary algorithm                               │
│      - Validate: each part ≤ maxPartSizeMb                          │
│      - Validate: total parts ≤ maxParts                             │
│    • On failure: Raise appropriate error                            │
│    • Store: splitPlan[] variable                                    │
│                                                                     │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ STEP 7: Dry Run Check                                       │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  [Choice Router]                                                    │
│    │                                                                │
│    ├── [When: dryRun = true]                                        │
│    │     │                                                          │
│    │     ├── [Transform: Build Dry Run Response]                    │
│    │     │     • status: "DRY_RUN"                                  │
│    │     │     • parts[].contentVersionId: null                     │
│    │     │     • parts[].contentDocumentId: null                    │
│    │     │                                                          │
│    │     ├── [Flow Reference: cleanup-temp-files]                   │
│    │     │                                                          │
│    │     ├── [Logger: DRY_RUN_COMPLETE]                             │
│    │     │                                                          │
│    │     └── [Return 200 Response]                                  │
│    │                                                                │
│    └── [Otherwise] → Continue to Step 8                             │
│                                                                     │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ STEP 8: Execute Split                                       │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  [Flow Reference: pdf-split-execution-subflow]                      │
│    • For each part in splitPlan:                                    │
│      - Java Component: Extract pages to new PDF                     │
│      - Write to temp file: {originalName}_part{NN}.pdf              │
│      - Verify size ≤ limit                                          │
│    • Store: partFiles[] variable                                    │
│                                                                     │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ STEP 9: Upload Parts with Transaction Control               │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  [Try Scope]                                                        │
│    │                                                                │
│    ├── [Object Store: Store IN_PROGRESS]                            │
│    │     • Key: idempotencyKey                                      │
│    │     • Value: {status: "IN_PROGRESS", correlationId}            │
│    │                                                                │
│    ├── [Set Variable: uploadedParts = []]                           │
│    │                                                                │
│    ├── [For Each: partFiles]                                        │
│    │     │                                                          │
│    │     └── [Flow Reference: upload-part-to-sf]                    │
│    │           • Create ContentVersion                              │
│    │           • Query ContentDocumentId                            │
│    │           • Create ContentDocumentLink                         │
│    │           • Append to uploadedParts[]                          │
│    │           • Logger: PART_UPLOADED                              │
│    │                                                                │
│    ├── [Object Store: Store COMPLETED]                              │
│    │     • Key: idempotencyKey                                      │
│    │     • Value: {status: "COMPLETED", result: {...}}              │
│    │     • TTL: 24 hours                                            │
│    │                                                                │
│    └── [On Error Propagate]                                         │
│          │                                                          │
│          ├── [Flow Reference: cleanup-created-parts]                │
│          │     • Delete ContentDocuments created so far             │
│          │                                                          │
│          ├── [Object Store: Store FAILED]                           │
│          │     • Key: idempotencyKey                                │
│          │     • Value: {status: "FAILED", error: {...}}            │
│          │                                                          │
│          └── [Rethrow Error]                                        │
│                                                                     │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ STEP 10: Finalize and Respond                               │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  [Flow Reference: cleanup-temp-files]                               │
│    • Delete temp directory and all files                            │
│                                                                     │
│  [Transform: Build Success Response]                                │
│    • status: "COMPLETED"                                            │
│    • Include all part details with SF IDs                           │
│                                                                     │
│  [Logger: SPLIT_COMPLETED]                                          │
│    • Level: INFO                                                    │
│    • Data: {correlationId, partCount, totalSizeBytes, durationMs}   │
│                                                                     │
│  [Return 200 Response]                                              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Asynchronous Job Flow

### Flow: split-async-flow

**Purpose:** Create async split job and return immediately

```
┌─────────────────────────────────────────────────────────────────────┐
│  FLOW: split-async-flow                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  [Flow Reference: generate-correlation-id]                          │
│                                                                     │
│  [Set Variables]                                                    │
│    • jobId ← "job_" + UUID.randomUUID()                             │
│    • claimId, contentDocumentId, maxPartSizeMb, maxParts            │
│                                                                     │
│  [Flow Reference: validate-input-params]                            │
│                                                                     │
│  [Flow Reference: salesforce-validation-subflow]                    │
│    • Same validation as sync flow                                   │
│                                                                     │
│  [Flow Reference: check-idempotency-async]                          │
│    • If existing job in progress → Return existing jobId (202)      │
│    • If completed job exists → Return existing result               │
│                                                                     │
│  [Object Store: Create Job Record]                                  │
│    • Key: jobId                                                     │
│    • Value: {                                                       │
│        status: "ACCEPTED",                                          │
│        claimId, contentDocumentId,                                  │
│        maxPartSizeMb, maxParts,                                     │
│        correlationId,                                               │
│        createdAt: now()                                             │
│      }                                                              │
│    • TTL: 24 hours                                                  │
│                                                                     │
│  [VM Publish: split-job-queue]                                      │
│    • Queue: split-job-queue (persistent)                            │
│    • Payload: {jobId, claimId, contentDocumentId, params}           │
│                                                                     │
│  [Set Response]                                                     │
│    • HTTP Status: 202 Accepted                                      │
│    • Header: Location → /split-jobs/{jobId}                         │
│    • Body: {jobId, status, statusUrl, createdAt, message}           │
│                                                                     │
│  [Logger: JOB_ACCEPTED]                                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Job Worker Flow

### Flow: job-worker-flow

**Purpose:** Background processor for async split jobs

```
┌─────────────────────────────────────────────────────────────────────┐
│  FLOW: job-worker-flow                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  [VM Listener: split-job-queue]                                     │
│    • Queue: split-job-queue                                         │
│    • Max Concurrency: ${async.worker.maxConcurrency}                │
│    • Acknowledgment: MANUAL (after processing)                      │
│                                                                     │
│         │                                                           │
│         ▼                                                           │
│  [Try Scope: Process Job]                                           │
│    │                                                                │
│    ├── [Set Variables from Message]                                 │
│    │     • jobId, claimId, contentDocumentId, params                │
│    │                                                                │
│    ├── [Object Store: Update Status → VALIDATING]                   │
│    │     • Update progress: {currentStep, completedSteps: 0}        │
│    │                                                                │
│    ├── [Flow Reference: pdf-download-subflow]                       │
│    │     • Before: Update status → DOWNLOADING                      │
│    │     • After: Update progress: {completedSteps: 1}              │
│    │                                                                │
│    ├── [Flow Reference: pdf-split-planning-subflow]                 │
│    │     • Before: Update status → SPLITTING                        │
│    │     • After: Update progress: {completedSteps: 2}              │
│    │                                                                │
│    ├── [Flow Reference: pdf-split-execution-subflow]                │
│    │     • After: Update progress: {completedSteps: 3}              │
│    │                                                                │
│    ├── [Object Store: Update Status → UPLOADING]                    │
│    │                                                                │
│    ├── [For Each: parts]                                            │
│    │     │                                                          │
│    │     ├── [Flow Reference: upload-part-to-sf]                    │
│    │     │                                                          │
│    │     └── [Object Store: Update Progress]                        │
│    │           • percentComplete: (3 + partIndex) / totalSteps      │
│    │                                                                │
│    ├── [Object Store: Store COMPLETED Result]                       │
│    │     • status: "COMPLETED"                                      │
│    │     • completedAt: now()                                       │
│    │     • result: {full split response}                            │
│    │                                                                │
│    ├── [Flow Reference: cleanup-temp-files]                         │
│    │                                                                │
│    └── [Logger: JOB_COMPLETED]                                      │
│                                                                     │
│    [On Error Continue]                                              │
│      │                                                              │
│      ├── [Flow Reference: cleanup-created-parts]                    │
│      │                                                              │
│      ├── [Flow Reference: cleanup-temp-files]                       │
│      │                                                              │
│      ├── [Object Store: Store FAILED]                               │
│      │     • status: "FAILED"                                       │
│      │     • completedAt: now()                                     │
│      │     • error: {errorCode, message, details, retryable}        │
│      │                                                              │
│      └── [Logger: JOB_FAILED]                                       │
│            • Level: ERROR                                           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

### Flow: job-status-flow

**Purpose:** Retrieve job status

```
┌─────────────────────────────────────────────────────────────────────┐
│  FLOW: job-status-flow                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  [Flow Reference: generate-correlation-id]                          │
│                                                                     │
│  [Set Variable: jobId from URI param]                               │
│                                                                     │
│  [Object Store: Retrieve Job Record]                                │
│    • Key: jobId                                                     │
│    • On Not Found: Raise JOB_NOT_FOUND error                        │
│                                                                     │
│  [Transform: Build Job Status Response]                             │
│    • Include: jobId, status, progress, timestamps                   │
│    • If COMPLETED: include result                                   │
│    • If FAILED: include error                                       │
│                                                                     │
│  [Return 200 Response]                                              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Subflows

### Subflow: generate-correlation-id

```
Extract X-Correlation-Id header
If present → Use as correlationId
If absent → Generate UUID
Store in variable: correlationId
Set response header: X-Correlation-Id
```

### Subflow: validate-input-params

```
Validate claimId:
  • Pattern: ^[a-zA-Z0-9]{15}|[a-zA-Z0-9]{18}$
  • On failure: Raise VALIDATION_ERROR

Validate contentDocumentId:
  • Pattern: ^069[a-zA-Z0-9]{12,15}$
  • On failure: Raise VALIDATION_ERROR
```

### Subflow: salesforce-validation-subflow

```
[Salesforce Query: Verify Claim]
  • SOQL: SELECT Id FROM Claim__c WHERE Id = :claimId LIMIT 1
  • On empty: Raise CLAIM_NOT_FOUND

[Salesforce Query: Verify Document Link]
  • SOQL: SELECT Id, ContentDocumentId
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :claimId
          AND ContentDocumentId = :contentDocumentId
          LIMIT 1
  • On empty: Raise DOCUMENT_NOT_LINKED_TO_CLAIM

[Salesforce Query: Fetch ContentVersion]
  • SOQL: SELECT Id, Title, FileExtension, ContentSize,
                 PathOnClient, VersionNumber, ContentBodyId
          FROM ContentVersion
          WHERE ContentDocumentId = :contentDocumentId
          AND IsLatest = true
          LIMIT 1
  • On empty: Raise DOCUMENT_NOT_FOUND

[Choice: Validate PDF]
  • If FileExtension != 'pdf': Raise NOT_A_PDF

Store: contentVersionMetadata
```

### Subflow: pdf-download-subflow

```
[Create Temp Directory]
  • Path: ${mule.home}/temp/pdf-split/{correlationId}/

[HTTP Request: Download VersionData]
  • Method: GET
  • URL: {sfInstanceUrl}/services/data/{apiVersion}/sobjects/
         ContentVersion/{contentVersionId}/VersionData
  • Streaming: ALWAYS
  • Auth: Bearer {sfAccessToken}

[File Write: Stream to Temp]
  • Path: {tempDir}/source.pdf
  • Mode: STREAM

Store: tempFilePath
Logger: PDF_DOWNLOADED
```

### Subflow: pdf-split-planning-subflow

```
[Java Component: PDF Analyzer]
  • Input: tempFilePath
  • Output: {pageCount, pageSizes[], totalSize, isValid}
  • On invalid: Raise INVALID_PDF

[Java Component: Split Planner]
  • Input: pageSizes[], maxPartSizeMb, maxParts
  • Algorithm: Greedy page-boundary
  • Validate: Single page not > maxPartSizeMb
  • Validate: Total parts ≤ maxParts
  • Output: splitPlan[]

Store: splitPlan
```

### Subflow: upload-part-to-sf

```
[Until Successful: Create ContentVersion]
  • Max Retries: 3
  • Interval: 2000ms

  [Salesforce Create: ContentVersion]
    • Title: {originalTitle}_part{NN}
    • PathOnClient: {originalName}_part{NN}.pdf
    • VersionData: {base64 encoded part}

[Salesforce Query: Get ContentDocumentId]
  • SELECT ContentDocumentId FROM ContentVersion WHERE Id = :newId

[Until Successful: Create ContentDocumentLink]
  • Max Retries: 3

  [Salesforce Create: ContentDocumentLink]
    • ContentDocumentId: {from query}
    • LinkedEntityId: {claimId}
    • ShareType: "V"
    • Visibility: "AllUsers"

Store part result: {partNumber, contentVersionId, contentDocumentId,
                    contentDocumentLinkId, fileName, sizeBytes}
```

### Subflow: cleanup-created-parts

```
For each part in uploadedParts (reverse order):
  [Try]
    [Salesforce Delete: ContentDocument]
      • ID: part.contentDocumentId
  [On Error Continue]
    Logger: CLEANUP_PARTIAL_FAILURE (warn)

Logger: CLEANUP_EXECUTED
```

### Subflow: cleanup-temp-files

```
[File Delete: Temp Directory]
  • Path: {tempDir}
  • Recursive: true
  • On failure: Log warning, continue
```

---

## Global Error Handler

```
┌─────────────────────────────────────────────────────────────────────┐
│  GLOBAL ERROR HANDLER                                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  [On Error Propagate: VALIDATION_ERROR]                             │
│    • HTTP Status: 400                                               │
│    • retryable: false                                               │
│                                                                     │
│  [On Error Propagate: UNAUTHORIZED]                                 │
│    • HTTP Status: 401                                               │
│    • retryable: false                                               │
│                                                                     │
│  [On Error Propagate: FORBIDDEN]                                    │
│    • HTTP Status: 403                                               │
│    • retryable: false                                               │
│                                                                     │
│  [On Error Propagate: CLAIM_NOT_FOUND]                              │
│    • HTTP Status: 404                                               │
│    • retryable: false                                               │
│                                                                     │
│  [On Error Propagate: DOCUMENT_NOT_FOUND]                           │
│    • HTTP Status: 404                                               │
│    • retryable: false                                               │
│                                                                     │
│  [On Error Propagate: DOCUMENT_NOT_LINKED_TO_CLAIM]                 │
│    • HTTP Status: 409                                               │
│    • retryable: false                                               │
│                                                                     │
│  [On Error Propagate: NOT_A_PDF]                                    │
│    • HTTP Status: 422                                               │
│    • retryable: false                                               │
│                                                                     │
│  [On Error Propagate: INVALID_PDF]                                  │
│    • HTTP Status: 422                                               │
│    • retryable: false                                               │
│                                                                     │
│  [On Error Propagate: PDF_TOO_LARGE_FOR_POLICY]                     │
│    • HTTP Status: 422                                               │
│    • retryable: false                                               │
│                                                                     │
│  [On Error Propagate: SINGLE_PAGE_EXCEEDS_LIMIT]                    │
│    • HTTP Status: 422                                               │
│    • retryable: false                                               │
│                                                                     │
│  [On Error Propagate: SALESFORCE_RATE_LIMIT]                        │
│    • HTTP Status: 429                                               │
│    • Header: Retry-After                                            │
│    • retryable: true                                                │
│                                                                     │
│  [On Error Propagate: SALESFORCE_AUTH_FAILURE]                      │
│    • HTTP Status: 502                                               │
│    • retryable: true                                                │
│                                                                     │
│  [On Error Propagate: SALESFORCE_UPSTREAM_ERROR]                    │
│    • HTTP Status: 502                                               │
│    • retryable: true                                                │
│                                                                     │
│  [On Error Propagate: PROCESSING_TIMEOUT]                           │
│    • HTTP Status: 504                                               │
│    • retryable: true                                                │
│                                                                     │
│  [On Error Propagate: Any]                                          │
│    • HTTP Status: 500                                               │
│    • Logger: Full stack trace (internal only)                       │
│    • retryable: true                                                │
│                                                                     │
│  All handlers:                                                      │
│    • Transform to ErrorResponse schema                              │
│    • Include correlationId                                          │
│    • Include timestamp (Asia/Kolkata)                               │
│    • Mask sensitive data in details                                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Connector Configuration

### HTTP Listener Config
```
Name: http-listener-config
Host: 0.0.0.0
Port: ${http.port}
Base Path: /
```

### Salesforce Config
```
Name: salesforce-config
Auth: OAuth 2.0 Client Credentials
Consumer Key: ${secure::sf.clientId}
Consumer Secret: ${secure::sf.clientSecret}
Token URL: ${salesforce.authUrl}
Instance URL: ${salesforce.instanceUrl}
API Version: ${salesforce.apiVersion}
```

### Object Store Config
```
Name: idempotency-object-store
Persistent: true
TTL: ${objectStore.idempotency.ttlMs}
Max Entries: ${objectStore.idempotency.maxEntries}

Name: jobs-object-store
Persistent: true
TTL: ${objectStore.jobs.ttlMs}
```

### VM Queue Config
```
Name: split-job-queue
Queue Type: PERSISTENT
Max Outstanding Messages: 100
```

---

## Retry Strategy

### Salesforce API Calls
```
Strategy: Until Successful
Max Retries: ${retry.salesforce.maxAttempts}
Interval: ${retry.salesforce.intervalMs}
Multiplier: ${retry.salesforce.multiplier}
Retry On:
  - CONNECTIVITY errors
  - HTTP 500, 502, 503, 504
  - SALESFORCE:TIMEOUT
```

### VM Queue Redelivery
```
Max Redelivery: 3
Redelivery Delay: 5000ms
Dead Letter Queue: split-job-dlq
```
