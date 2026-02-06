# Salesforce PDF Split System API — Technical Documentation

## 1. Overview

### Purpose
The Salesforce PDF Split System API is a **System API (SYS)** that splits large PDF documents stored in Salesforce into smaller sequential parts. Each part is re-uploaded to Salesforce and linked to the original claim record. This API addresses Salesforce file size limitations by automatically dividing oversized PDFs.

### Audience
- Developers integrating with the EXP API layer
- Integration analysts designing claim document workflows
- Operations teams troubleshooting document processing

### Key Capabilities
| Capability | Description |
|------------|-------------|
| Synchronous Split | Split PDFs immediately with real-time response |
| Asynchronous Split | Queue large PDF splits as background jobs |
| Dry Run Mode | Validate and preview splits without uploading |
| Job Management | List, monitor, and cancel async split jobs |
| Idempotency | Automatic caching prevents duplicate processing |

### High-Level Flow (SYS API Role)
```
EXP API → [This SYS API] → Salesforce
                ↓
         1. Download PDF from SF ContentVersion
         2. Split using Apache PDFBox
         3. Upload parts as new ContentVersions
         4. Link parts to original Claim
```

---

## 2. Environment & Base URLs

| Environment | Base URL | Notes |
|-------------|----------|-------|
| DEV | `TBD / Provide:` DEV CloudHub URL | Development testing |
| UAT | `https://lwcc-sf-doc-split-sys-uat-<worker>.cloudhub.io` | User acceptance testing |
| PROD | `TBD / Provide:` PROD CloudHub URL | Production |

**Base Path:** `/sys/sf-doc-split/v1`

> **Note:** This SYS API is consumed by the EXP API layer, not called directly by external clients.

---

## 3. Authentication & Authorization

### Auth Type
**Client ID / Client Secret** enforcement via Anypoint API Manager.

### Required Headers
| Header | Required | Description |
|--------|----------|-------------|
| `client_id` | Yes | API client identifier |
| `client_secret` | Yes | API client secret |

### Example Header Block
```http
client_id: your-client-id-here
client_secret: your-client-secret-here
Content-Type: application/json
X-Correlation-Id: 550e8400-e29b-41d4-a716-446655440000
```

### How to Obtain Credentials
`TBD / Provide:` Process for requesting client credentials (e.g., via Anypoint Exchange, API Manager, or internal request).

---

## 4. Common Standards

### 4.1 Headers

| Header | Required | Description | Example |
|--------|----------|-------------|---------|
| `client_id` | Yes | API client identifier | `abc123` |
| `client_secret` | Yes | API client secret | `secret456` |
| `Content-Type` | Yes (POST) | Media type | `application/json` |
| `X-Correlation-Id` | No | Request tracing ID (auto-generated if missing) | `550e8400-e29b-41d4-a716-446655440000` |

### 4.2 Idempotency
- **Key:** `{claimId}|{contentDocumentId}|{contentVersionId}`
- **Behavior:** Repeat requests return cached results unless `forceRefresh=true`
- **TTL:** Results cached in Object Store (configurable)

### 4.3 Pagination / Sorting / Filtering
Applies to `GET /split-jobs` endpoint only:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | integer | 20 | Max results (1-100) |
| `status` | string | — | Filter by job status |
| `claimId` | string | — | Filter by claim ID |

### 4.4 Rate Limits / Policies
`TBD / Provide:` Confirm if any API Manager policies are applied (rate limiting, spike control, IP allowlist).

### 4.5 Correlation ID & Tracing
- Pass `X-Correlation-Id` header for end-to-end tracing
- If not provided, a UUID is auto-generated
- All responses include `correlationId` in the body
- Logs are tagged with correlation ID for debugging

### 4.6 Date/Time Formats and Timezone
- **Format:** ISO 8601 with timezone offset
- **Example:** `2026-01-20T14:35:22+05:30`

### 4.7 Naming Conventions
- Split parts are named: `{originalFileName}_part{NN}.pdf`
- Example: `ClaimEvidence_2026_part01.pdf`, `ClaimEvidence_2026_part02.pdf`

---

## 5. Endpoints

### 5.1 GET /healthcheck

**Description:** Returns service health status and dependency health.

**Use Cases:**
- Load balancer health probes
- Monitoring dashboards
- Pre-flight checks before batch processing

**Headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `client_id` | No | Not required for health check |

**Parameters:** None

**Responses:**

**200 OK — Service Healthy**
```json
{
  "status": "healthy",
  "version": "1.0.1",
  "timestamp": "2026-01-20T14:30:00+05:30",
  "uptime": "2d 14h 32m",
  "uptimeSeconds": 225120
}
```

---

### 5.2 POST /claims/{claimId}/documents/{contentDocumentId}/split

**Description:** Validates and splits a PDF document synchronously. The API downloads the PDF from Salesforce, splits it into parts, uploads each part, and links them to the claim.

**Use Cases:**
- Split documents under ~50MB where immediate response is acceptable
- Preview splits with `dryRun=true` before committing
- Re-process documents with `forceRefresh=true`

**Headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `client_id` | Yes | API client identifier |
| `client_secret` | Yes | API client secret |
| `Content-Type` | No | Not required (no request body) |
| `X-Correlation-Id` | No | Request tracing ID |

**Path Parameters:**

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `claimId` | string | Yes | Salesforce Claim record ID | `a0B5g00000AbCdEfGh` |
| `contentDocumentId` | string | Yes | Salesforce ContentDocument ID | `069Hp00000BcDeFgHi` |

**Query Parameters:**

| Parameter | Type | Required | Default | Constraints | Description |
|-----------|------|----------|---------|-------------|-------------|
| `maxPartSizeMb` | integer | No | 15 | 1-15 | Maximum size per part in MB |
| `maxParts` | integer | No | 5 | 1-5 | Maximum number of parts allowed |
| `dryRun` | boolean | No | false | — | If true, validates without uploading |
| `forceRefresh` | boolean | No | false | — | If true, bypasses idempotency cache |

**Request Body:** None

**Responses:**

**200 OK — Split Completed**
```json
{
  "claimId": "a0B5g00000AbCdEfGh",
  "sourceContentDocumentId": "069Hp00000BcDeFgHi",
  "sourceContentVersionId": "068Hp00000CdEfGhIj",
  "originalFileName": "ClaimEvidence_2026.pdf",
  "originalSizeBytes": 47185920,
  "originalPageCount": 156,
  "partCount": 4,
  "status": "COMPLETED",
  "dryRun": false,
  "parts": [
    {
      "partNumber": 1,
      "pageStart": 1,
      "pageEnd": 42,
      "pageCount": 42,
      "sizeBytes": 14728192,
      "sizeMb": 14.04,
      "contentVersionId": "068Hp00000AAAA001",
      "contentDocumentId": "069Hp00000BBBB001",
      "contentDocumentLinkId": "06AHp00000CCCC001",
      "fileName": "ClaimEvidence_2026_part01.pdf"
    },
    {
      "partNumber": 2,
      "pageStart": 43,
      "pageEnd": 81,
      "pageCount": 39,
      "sizeBytes": 14155776,
      "sizeMb": 13.50,
      "contentVersionId": "068Hp00000AAAA002",
      "contentDocumentId": "069Hp00000BBBB002",
      "contentDocumentLinkId": "06AHp00000CCCC002",
      "fileName": "ClaimEvidence_2026_part02.pdf"
    },
    {
      "partNumber": 3,
      "pageStart": 82,
      "pageEnd": 118,
      "pageCount": 37,
      "sizeBytes": 13631488,
      "sizeMb": 13.00,
      "contentVersionId": "068Hp00000AAAA003",
      "contentDocumentId": "069Hp00000BBBB003",
      "contentDocumentLinkId": "06AHp00000CCCC003",
      "fileName": "ClaimEvidence_2026_part03.pdf"
    },
    {
      "partNumber": 4,
      "pageStart": 119,
      "pageEnd": 156,
      "pageCount": 38,
      "sizeBytes": 4670464,
      "sizeMb": 4.45,
      "contentVersionId": "068Hp00000AAAA004",
      "contentDocumentId": "069Hp00000BBBB004",
      "contentDocumentLinkId": "06AHp00000CCCC004",
      "fileName": "ClaimEvidence_2026_part04.pdf"
    }
  ],
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-01-20T14:35:22+05:30"
}
```

**Errors:**

| Status | Error Code | When It Happens |
|--------|------------|-----------------|
| 400 | `VALIDATION_ERROR` | Invalid query parameters (e.g., maxPartSizeMb > 15) |
| 400 | `NOT_A_PDF` | Document file extension is not PDF |
| 400 | `INVALID_PDF` | PDF is corrupted or cannot be processed |
| 400 | `PDF_TOO_LARGE_FOR_POLICY` | PDF requires more than 5 parts |
| 400 | `SINGLE_PAGE_EXCEEDS_LIMIT` | A single page exceeds 15MB |
| 401 | `UNAUTHORIZED` | Missing or invalid client credentials |
| 404 | `CLAIM_NOT_FOUND` | Claim record does not exist in Salesforce |
| 404 | `DOCUMENT_NOT_FOUND` | ContentDocument does not exist |
| 404 | `DOCUMENT_NOT_LINKED_TO_CLAIM` | Document is not linked to the specified claim |
| 500 | `SALESFORCE_AUTH_FAILURE` | Failed to authenticate with Salesforce |
| 500 | `SALESFORCE_UPSTREAM_ERROR` | Salesforce returned an error |
| 500 | `PROCESSING_TIMEOUT` | Processing exceeded maximum allowed time |
| 500 | `INTERNAL_ERROR` | Unexpected internal error |

**Error Response Example (404):**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "DOCUMENT_NOT_LINKED_TO_CLAIM",
  "message": "The specified document is not linked to this claim",
  "details": {
    "claimId": "a0B5g00000AbCdEfGh",
    "contentDocumentId": "069Hp00000BcDeFgHi"
  },
  "retryable": false
}
```

**Notes:**
- Synchronous processing blocks until complete
- For large files, consider using the async `/split-jobs` endpoint
- Idempotent: repeat calls return cached results unless `forceRefresh=true`

---

### 5.3 POST /claims/{claimId}/documents/{contentDocumentId}/split-jobs

**Description:** Initiates an asynchronous PDF split job. Returns immediately with a job ID for status polling.

**Use Cases:**
- Large PDFs where synchronous timeout is a concern
- Batch processing with webhook callbacks
- Non-blocking integrations

**Headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `client_id` | Yes | API client identifier |
| `client_secret` | Yes | API client secret |
| `X-Correlation-Id` | No | Request tracing ID |

**Path Parameters:**

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `claimId` | string | Yes | Salesforce Claim record ID | `a0B5g00000AbCdEfGh` |
| `contentDocumentId` | string | Yes | Salesforce ContentDocument ID | `069Hp00000BcDeFgHi` |

**Query Parameters:**

| Parameter | Type | Required | Default | Constraints | Description |
|-----------|------|----------|---------|-------------|-------------|
| `maxPartSizeMb` | integer | No | 15 | 1-15 | Maximum size per part in MB |
| `maxParts` | integer | No | 5 | 1-5 | Maximum parts allowed |
| `callbackUrl` | string | No | — | Must be HTTPS | Webhook URL for completion notification |

**Request Body:** None

**Responses:**

**202 Accepted — Job Queued**
```json
{
  "jobId": "job_7f3a8c2d-1e4b-5f6a-9c0d-2e3f4a5b6c7d",
  "status": "ACCEPTED",
  "statusUrl": "/split-jobs/job_7f3a8c2d-1e4b-5f6a-9c0d-2e3f4a5b6c7d",
  "createdAt": "2026-01-20T14:30:00+05:30",
  "message": "Split job accepted and queued for processing"
}
```

**Errors:** Same as synchronous split endpoint (400, 401, 404, 500).

---

### 5.4 GET /split-jobs

**Description:** List split jobs with optional filtering.

**Use Cases:**
- Monitor active jobs
- Find failed jobs for retry
- Dashboard/reporting

**Headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `client_id` | Yes | API client identifier |
| `client_secret` | Yes | API client secret |

**Query Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `status` | string | No | — | Filter by status: `ACCEPTED`, `VALIDATING`, `DOWNLOADING`, `SPLITTING`, `UPLOADING`, `COMPLETED`, `FAILED` |
| `claimId` | string | No | — | Filter by claim ID |
| `limit` | integer | No | 20 | Max results (1-100) |

**Responses:**

**200 OK**
```json
{
  "jobs": [
    {
      "jobId": "job_7f3a8c2d-1e4b-5f6a-9c0d-2e3f4a5b6c7d",
      "status": "COMPLETED",
      "claimId": "a0B5g00000AbCdEfGh",
      "createdAt": "2026-01-20T14:30:00+05:30"
    }
  ],
  "pagination": {
    "total": 1,
    "limit": 20,
    "offset": 0
  }
}
```

---

### 5.5 GET /split-jobs/{jobId}

**Description:** Returns the current status and results of an async split job.

**Use Cases:**
- Poll for job completion
- Retrieve split results after async processing
- Debug failed jobs

**Headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `client_id` | Yes | API client identifier |
| `client_secret` | Yes | API client secret |

**Path Parameters:**

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `jobId` | string | Yes | Job identifier | `job_7f3a8c2d-1e4b-5f6a-9c0d-2e3f4a5b6c7d` |

**Responses:**

**200 OK — Job Completed**
```json
{
  "jobId": "job_7f3a8c2d-1e4b-5f6a-9c0d-2e3f4a5b6c7d",
  "status": "COMPLETED",
  "progress": {
    "currentStep": "Complete",
    "completedSteps": 5,
    "totalSteps": 5,
    "percentComplete": 100
  },
  "createdAt": "2026-01-20T14:30:00+05:30",
  "startedAt": "2026-01-20T14:30:02+05:30",
  "completedAt": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "result": {
    "claimId": "a0B5g00000AbCdEfGh",
    "sourceContentDocumentId": "069Hp00000BcDeFgHi",
    "sourceContentVersionId": "068Hp00000CdEfGhIj",
    "originalFileName": "ClaimEvidence_2026.pdf",
    "originalSizeBytes": 47185920,
    "originalPageCount": 156,
    "partCount": 4,
    "status": "COMPLETED",
    "dryRun": false,
    "parts": [
      {
        "partNumber": 1,
        "pageStart": 1,
        "pageEnd": 42,
        "pageCount": 42,
        "sizeBytes": 14728192,
        "sizeMb": 14.04,
        "contentVersionId": "068Hp00000AAAA001",
        "contentDocumentId": "069Hp00000BBBB001",
        "contentDocumentLinkId": "06AHp00000CCCC001",
        "fileName": "ClaimEvidence_2026_part01.pdf"
      },
      {
        "partNumber": 2,
        "pageStart": 43,
        "pageEnd": 81,
        "pageCount": 39,
        "sizeBytes": 14155776,
        "sizeMb": 13.50,
        "contentVersionId": "068Hp00000AAAA002",
        "contentDocumentId": "069Hp00000BBBB002",
        "contentDocumentLinkId": "06AHp00000CCCC002",
        "fileName": "ClaimEvidence_2026_part02.pdf"
      },
      {
        "partNumber": 3,
        "pageStart": 82,
        "pageEnd": 118,
        "pageCount": 37,
        "sizeBytes": 13631488,
        "sizeMb": 13.00,
        "contentVersionId": "068Hp00000AAAA003",
        "contentDocumentId": "069Hp00000BBBB003",
        "contentDocumentLinkId": "06AHp00000CCCC003",
        "fileName": "ClaimEvidence_2026_part03.pdf"
      },
      {
        "partNumber": 4,
        "pageStart": 119,
        "pageEnd": 156,
        "pageCount": 38,
        "sizeBytes": 4670464,
        "sizeMb": 4.45,
        "contentVersionId": "068Hp00000AAAA004",
        "contentDocumentId": "069Hp00000BBBB004",
        "contentDocumentLinkId": "06AHp00000CCCC004",
        "fileName": "ClaimEvidence_2026_part04.pdf"
      }
    ],
    "correlationId": "550e8400-e29b-41d4-a716-446655440000",
    "timestamp": "2026-01-20T14:35:22+05:30"
  }
}
```

**200 OK — Job In Progress**
```json
{
  "jobId": "job_7f3a8c2d-1e4b-5f6a-9c0d-2e3f4a5b6c7d",
  "status": "SPLITTING",
  "progress": {
    "currentStep": "Splitting PDF into parts",
    "completedSteps": 2,
    "totalSteps": 5,
    "percentComplete": 40
  },
  "createdAt": "2026-01-20T14:30:00+05:30",
  "startedAt": "2026-01-20T14:30:02+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000"
}
```

**404 Not Found — Job Not Found**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "JOB_NOT_FOUND",
  "message": "Split job not found or has expired",
  "details": {
    "jobId": "job_7f3a8c2d-1e4b-5f6a-9c0d-2e3f4a5b6c7d",
    "hint": "Job records are retained for 24 hours after completion"
  },
  "retryable": false
}
```

---

### 5.6 DELETE /split-jobs/{jobId}

**Description:** Cancels a pending or in-progress split job.

**Use Cases:**
- Cancel jobs queued in error
- Abort long-running jobs

**Headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `client_id` | Yes | API client identifier |
| `client_secret` | Yes | API client secret |

**Path Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `jobId` | string | Yes | Job identifier |

**Responses:**

| Status | Description |
|--------|-------------|
| 204 No Content | Job cancelled successfully |
| 400 Bad Request | Job cannot be cancelled (already completed/failed) |
| 404 Not Found | Job not found |

---

## 6. Data Models

### 6.1 SplitResponse

| Field | Type | Description |
|-------|------|-------------|
| `claimId` | string | Salesforce Claim record ID |
| `sourceContentDocumentId` | string | Original ContentDocumentId |
| `sourceContentVersionId` | string | Source ContentVersionId |
| `originalFileName` | string | Original PDF file name |
| `originalSizeBytes` | integer | Original file size in bytes |
| `originalPageCount` | integer | Total pages in original PDF |
| `partCount` | integer | Number of parts created (1-5) |
| `status` | string | `COMPLETED` or `DRY_RUN` |
| `dryRun` | boolean | Whether this was a dry run |
| `parts` | array | Array of PartDetail objects |
| `correlationId` | string | Request correlation ID |
| `timestamp` | datetime | Response timestamp (ISO 8601) |

### 6.2 PartDetail

| Field | Type | Description |
|-------|------|-------------|
| `partNumber` | integer | Sequential part number (1-5) |
| `pageStart` | integer | First page number (1-indexed) |
| `pageEnd` | integer | Last page number |
| `pageCount` | integer | Total pages in this part |
| `sizeBytes` | integer | Part size in bytes |
| `sizeMb` | number | Part size in megabytes |
| `contentVersionId` | string | SF ContentVersionId (null for dry-run) |
| `contentDocumentId` | string | SF ContentDocumentId (null for dry-run) |
| `contentDocumentLinkId` | string | SF ContentDocumentLinkId (null for dry-run) |
| `fileName` | string | Part file name |

### 6.3 ErrorResponse

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | datetime | When the error occurred |
| `correlationId` | string | Request correlation ID |
| `errorCode` | string | Machine-readable error code |
| `message` | string | Human-readable message |
| `details` | object | Additional context (optional) |
| `retryable` | boolean | Whether request can be retried |

### 6.4 JobStatusResponse

| Field | Type | Description |
|-------|------|-------------|
| `jobId` | string | Unique job identifier (pattern: `job_<uuid>`) |
| `status` | string | `ACCEPTED`, `VALIDATING`, `DOWNLOADING`, `SPLITTING`, `UPLOADING`, `COMPLETED`, `FAILED` |
| `progress` | object | JobProgress object (optional) |
| `createdAt` | datetime | Job creation timestamp |
| `startedAt` | datetime | Processing start timestamp (optional) |
| `completedAt` | datetime | Completion timestamp (optional) |
| `correlationId` | string | Request correlation ID |
| `result` | object | SplitResponse (only when COMPLETED) |
| `error` | object | ErrorResponse (only when FAILED) |

### 6.5 JobProgress

| Field | Type | Description |
|-------|------|-------------|
| `currentStep` | string | Human-readable description of current step |
| `completedSteps` | integer | Number of steps completed |
| `totalSteps` | integer | Total number of steps |
| `percentComplete` | integer | Overall percentage (0-100) |

### 6.6 HealthResponse

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | `healthy`, `degraded`, or `unhealthy` |
| `version` | string | API version |
| `timestamp` | datetime | Health check timestamp |
| `uptime` | string | Human-readable uptime (optional) |
| `uptimeSeconds` | integer | Uptime in seconds (optional) |
| `dependencies` | object | Dependency health (optional) |
| `metrics` | object | Service metrics (optional) |

---

## 7. Error Handling

### Standard Error Format
All errors return JSON with consistent structure (see ErrorResponse model above).

### Error Code Catalog

| Error Code | HTTP Status | Description | Retryable |
|------------|-------------|-------------|-----------|
| `VALIDATION_ERROR` | 400 | Invalid input parameters | No |
| `UNAUTHORIZED` | 401 | Missing/invalid authentication | No |
| `FORBIDDEN` | 403 | Insufficient permissions | No |
| `CLAIM_NOT_FOUND` | 404 | Claim does not exist | No |
| `DOCUMENT_NOT_FOUND` | 404 | ContentDocument does not exist | No |
| `JOB_NOT_FOUND` | 404 | Job does not exist or expired | No |
| `DOCUMENT_NOT_LINKED_TO_CLAIM` | 404 | Document not linked to claim | No |
| `NOT_A_PDF` | 400 | File is not a PDF | No |
| `INVALID_PDF` | 400 | PDF is corrupted | No |
| `PDF_TOO_LARGE_FOR_POLICY` | 400 | PDF requires >5 parts | No |
| `SINGLE_PAGE_EXCEEDS_LIMIT` | 400 | Single page >15MB | No |
| `SALESFORCE_AUTH_FAILURE` | 500 | SF authentication failed | Yes |
| `SALESFORCE_RATE_LIMIT` | 500 | SF rate limit exceeded | Yes (with backoff) |
| `SALESFORCE_UPSTREAM_ERROR` | 500 | SF returned an error | Yes |
| `PROCESSING_TIMEOUT` | 500 | Processing timeout | Yes |
| `INTERNAL_ERROR` | 500 | Unexpected error | Yes |

### Retry Guidance
- **Retryable errors:** Wait 5-10 seconds, then retry with exponential backoff
- **Non-retryable errors:** Fix the request or data before retrying
- **Rate limit errors:** Wait at least 60 seconds before retry

---

## 8. Security Considerations

### PII Handling
- No PII is stored in API logs
- Salesforce record IDs are not considered PII

### Masking Rules
- SSN and social security numbers are masked in JSON logs
- Client secrets are never logged

### Transport Security
- HTTPS only (HTTP not supported)
- TLS 1.2+ required

---

## 9. Change Log

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0.0 | TBD | Initial release | TBD |
| 1.0.1 | TBD | Current version | TBD |

---

## 10. Appendix — cURL Examples

### Health Check
```bash
curl -X GET "https://<BASE_URL>/sys/sf-doc-split/v1/healthcheck"
```

### Split Document (Synchronous)
```bash
curl -X POST "https://<BASE_URL>/sys/sf-doc-split/v1/claims/a0B5g00000AbCdEfGh/documents/069Hp00000BcDeFgHi/split?maxPartSizeMb=15&maxParts=5" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>" \
  -H "X-Correlation-Id: 550e8400-e29b-41d4-a716-446655440000"
```

### Split Document (Dry Run)
```bash
curl -X POST "https://<BASE_URL>/sys/sf-doc-split/v1/claims/a0B5g00000AbCdEfGh/documents/069Hp00000BcDeFgHi/split?dryRun=true" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>" \
  -H "X-Correlation-Id: 550e8400-e29b-41d4-a716-446655440000"
```

### Split Document (Force Refresh)
```bash
curl -X POST "https://<BASE_URL>/sys/sf-doc-split/v1/claims/a0B5g00000AbCdEfGh/documents/069Hp00000BcDeFgHi/split?forceRefresh=true" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>" \
  -H "X-Correlation-Id: 550e8400-e29b-41d4-a716-446655440000"
```

### Create Async Split Job
```bash
curl -X POST "https://<BASE_URL>/sys/sf-doc-split/v1/claims/a0B5g00000AbCdEfGh/documents/069Hp00000BcDeFgHi/split-jobs?maxPartSizeMb=15&maxParts=5" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>" \
  -H "X-Correlation-Id: 550e8400-e29b-41d4-a716-446655440000"
```

### Create Async Split Job with Callback
```bash
curl -X POST "https://<BASE_URL>/sys/sf-doc-split/v1/claims/a0B5g00000AbCdEfGh/documents/069Hp00000BcDeFgHi/split-jobs?callbackUrl=https://your-app.com/webhook" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>" \
  -H "X-Correlation-Id: 550e8400-e29b-41d4-a716-446655440000"
```

### List Split Jobs
```bash
curl -X GET "https://<BASE_URL>/sys/sf-doc-split/v1/split-jobs?status=COMPLETED&limit=50" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>"
```

### List Split Jobs by Claim
```bash
curl -X GET "https://<BASE_URL>/sys/sf-doc-split/v1/split-jobs?claimId=a0B5g00000AbCdEfGh" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>"
```

### Get Job Status
```bash
curl -X GET "https://<BASE_URL>/sys/sf-doc-split/v1/split-jobs/job_7f3a8c2d-1e4b-5f6a-9c0d-2e3f4a5b6c7d" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>" \
  -H "X-Correlation-Id: 550e8400-e29b-41d4-a716-446655440000"
```

### Cancel Job
```bash
curl -X DELETE "https://<BASE_URL>/sys/sf-doc-split/v1/split-jobs/job_7f3a8c2d-1e4b-5f6a-9c0d-2e3f4a5b6c7d" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>" \
  -H "X-Correlation-Id: 550e8400-e29b-41d4-a716-446655440000"
```

---

## Items Marked TBD

The following items need to be provided to complete this documentation:

1. **Environment URLs:** DEV and PROD CloudHub base URLs
2. **Credential Process:** How to request client_id/client_secret
3. **API Policies:** Rate limiting, spike control, IP allowlist details (if any)
4. **Change Log:** Version dates and author information
