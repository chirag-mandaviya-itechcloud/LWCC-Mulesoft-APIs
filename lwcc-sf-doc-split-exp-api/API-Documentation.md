# LWCC SF Document Split Experience API — Technical Documentation

## 1. Overview

### Purpose
The LWCC SF Document Split Experience API is an **Experience API (EXP)** that provides a simplified, consumer-friendly interface for splitting large PDF documents stored in Salesforce. It acts as an orchestration layer that accepts document split requests and proxies them to the underlying System API.

### Audience
- External application developers consuming the API
- Integration analysts designing document processing workflows
- Mobile and web application teams
- Partner systems requiring document splitting capabilities

### Key Capabilities
| Capability | Description |
|------------|-------------|
| Document Splitting | Split large PDFs into smaller sequential parts |
| Simple Interface | Clean JSON request/response with minimal complexity |
| Request Tracing | Full correlation ID tracking for debugging |
| Input Validation | Salesforce ID validation at the API gateway level |
| Error Standardization | Consistent error format across all failure scenarios |

### High-Level Flow (EXP API Role)
```
Client Application
        ↓
   [This EXP API]  ←── Validates request, adds correlation ID
        ↓
   [SYS API]       ←── Performs actual PDF split in Salesforce
        ↓
   Salesforce
```

---

## 2. Environment & Base URLs

| Environment | Base URL | Notes |
|-------------|----------|-------|
| DEV | `TBD / Provide:` DEV CloudHub URL | Development testing |
| UAT | `https://lwcc-sf-doc-split-exp-uat-<worker>.cloudhub.io` | User acceptance testing |
| PROD | `TBD / Provide:` PROD CloudHub URL | Production |

**Base Path:** `/api`

---

## 3. Authentication & Authorization

### Auth Type
**Client ID / Client Secret** enforcement via HTTP headers.

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
X-Correlation-ID: 550e8400-e29b-41d4-a716-446655440000
```

### How to Obtain Credentials
`TBD / Provide:` Process for requesting client credentials (e.g., via Anypoint Exchange, API Manager, or internal request).

### Public Endpoints
The `/healthcheck` endpoint does **not** require authentication.

---

## 4. Common Standards

### 4.1 Headers

| Header | Required | Description | Example |
|--------|----------|-------------|---------|
| `client_id` | Yes* | API client identifier | `abc123` |
| `client_secret` | Yes* | API client secret | `secret456` |
| `Content-Type` | Yes (POST) | Media type | `application/json` |
| `X-Correlation-ID` | No | Request tracing ID (auto-generated if missing) | `550e8400-e29b-41d4-a716-446655440000` |

*Not required for `/healthcheck` endpoint

### 4.2 Idempotency
- Requests with `forceRefresh: false` may return cached results from the System API
- Default behavior is `forceRefresh: true` (always process fresh)

### 4.3 Correlation ID & Tracing
- Pass `X-Correlation-ID` header for end-to-end tracing
- If not provided, a UUID is auto-generated
- All responses include `correlationId` in the body
- Same correlation ID is propagated to the System API
- Logs are tagged with correlation ID for debugging

### 4.4 Date/Time Formats and Timezone
- **Format:** ISO 8601 with timezone
- **Example:** `2026-01-21T12:09:55Z`

### 4.5 Salesforce ID Format
- **Length:** 15 or 18 characters
- **Pattern:** `^[a-zA-Z0-9]{15,18}$`
- **Example:** `0ZkVA000000Ubyn0AC`

### 4.6 Rate Limits / Policies
`TBD / Provide:` Confirm if any API Manager policies are applied (rate limiting, spike control, IP allowlist).

---

## 5. Endpoints

### 5.1 GET /healthcheck

**Description:** Returns service health status. This is a public endpoint that does not require authentication.

**Use Cases:**
- Load balancer health probes
- Monitoring dashboards
- Pre-flight checks before batch processing

**Headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `client_id` | No | Not required for health check |
| `client_secret` | No | Not required for health check |

**Parameters:** None

**Request Body:** None

**Responses:**

**200 OK — Service Healthy**
```json
{
  "status": "UP",
  "timestamp": "2026-01-22T10:30:00.000+05:30",
  "version": "1.0.0"
}
```

---

### 5.2 POST /documents/split

**Description:** Initiates document split processing. Accepts claimId and documentId in the request body and proxies to the SF Doc Split System API.

**Use Cases:**
- Split large PDF documents attached to Salesforce claims
- Process documents that exceed Salesforce file size limits
- Automate document management workflows

**Headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `client_id` | Yes | API client identifier |
| `client_secret` | Yes | API client secret |
| `Content-Type` | Yes | Must be `application/json` |
| `X-Correlation-ID` | No | Request tracing ID (auto-generated if missing) |

**Parameters:** None (all data in request body)

**Request Body:**

| Field | Type | Required | Constraints | Description |
|-------|------|----------|-------------|-------------|
| `claimId` | string | Yes | 15-18 alphanumeric chars, pattern `^[a-zA-Z0-9]{15,18}$` | Salesforce Claim record ID |
| `documentId` | string | Yes | 15-18 alphanumeric chars, pattern `^[a-zA-Z0-9]{15,18}$` | Salesforce ContentDocument ID |
| `forceRefresh` | boolean | No | Default: `true` | If true, bypasses cache and processes fresh |

**Request Example:**
```json
{
  "claimId": "0ZkVA000000Ubyn0AC",
  "documentId": "069VA00000CB2CTYA1",
  "forceRefresh": true
}
```

**Responses:**

**200 OK — Split Completed**
```json
{
  "claimId": "0ZkVA000000Ubyd0AC",
  "sourceContentDocumentId": "069VA00000CBizjYAD",
  "sourceContentVersionId": "068VA00000E7c3jYAB",
  "originalFileName": "test_medium_image_heavy.pdf",
  "originalSizeBytes": 22905794,
  "originalPageCount": 12,
  "partCount": 2,
  "status": "COMPLETED",
  "dryRun": false,
  "parts": [
    {
      "partNumber": 1,
      "pageStart": 1,
      "pageEnd": 8,
      "pageCount": 8,
      "sizeBytes": 15270893,
      "sizeMb": 14.563458442687988,
      "contentVersionId": "068VA00000E7a3XYAR",
      "contentDocumentId": "069VA00000CBhApYAL",
      "contentDocumentLinkId": "06AVA00000DM4IR2A1",
      "fileName": "test_medium_image_heavy_part01.pdf"
    },
    {
      "partNumber": 2,
      "pageStart": 9,
      "pageEnd": 12,
      "pageCount": 4,
      "sizeBytes": 7636060,
      "sizeMb": 7.282314300537109,
      "contentVersionId": "068VA00000E7cN3YAJ",
      "contentDocumentId": "069VA00000CBjJ3YAL",
      "contentDocumentLinkId": "06AVA00000DLvfv2AD",
      "fileName": "test_medium_image_heavy_part02.pdf"
    }
  ],
  "correlationId": "713804e4-1fcb-4e49-ae2c-98765d6f7d5d",
  "timestamp": "2026-01-21T12:09:55Z"
}
```

**Errors:**

| Status | Error Code | When It Happens |
|--------|------------|-----------------|
| 400 | `BAD_REQUEST` | Missing or invalid claimId/documentId |
| 400 | `VALIDATION_ERROR` | Request body validation failed |
| 401 | `UNAUTHORIZED` | Missing or invalid client credentials |
| 404 | `NOT_FOUND` | Claim or document not found in Salesforce |
| 405 | `METHOD_NOT_ALLOWED` | Invalid HTTP method for endpoint |
| 406 | `NOT_ACCEPTABLE` | Invalid Accept header |
| 415 | `UNSUPPORTED_MEDIA_TYPE` | Invalid Content-Type header |
| 500 | `INTERNAL_ERROR` | Unexpected server error |
| 501 | `NOT_IMPLEMENTED` | Feature not implemented |
| 502 | `SYSTEM_API_ERROR` | System API error or timeout |

**Error Response Example (400 Bad Request):**
```json
{
  "errorCode": "BAD_REQUEST",
  "errorMessage": "FAILURE",
  "errorDescription": "claimId is required and cannot be blank",
  "transactionId": "exp-12345-abcde",
  "timeStamp": "2026-01-22T10:30:00.000Z"
}
```

**Error Response Example (404 Not Found):**
```json
{
  "errorCode": "NOT_FOUND",
  "errorMessage": "FAILURE",
  "errorDescription": "Claim record does not exist in Salesforce",
  "transactionId": "713804e4-1fcb-4e49-ae2c-98765d6f7d5d",
  "timeStamp": "2026-01-22T10:30:00.000Z"
}
```

**Error Response Example (502 System API Error):**
```json
{
  "errorCode": "SYSTEM_API_ERROR",
  "errorMessage": "FAILURE",
  "errorDescription": "HTTP POST on resource 'https://lwcc-sf-doc-split-sys-api...' failed: internal server error (500).",
  "transactionId": "713804e4-1fcb-4e49-ae2c-98765d6f7d5d",
  "timeStamp": "2026-01-22T10:30:00.000Z"
}
```

**Notes:**
- The `forceRefresh` parameter defaults to `true` if not provided
- Processing is synchronous — the API waits for the System API to complete
- Response timeout is 120 seconds
- For very large files, consider implementing async polling on the client side

---

## 6. Data Models

### 6.1 DocumentSplitRequest

| Field | Type | Required | Constraints | Description |
|-------|------|----------|-------------|-------------|
| `claimId` | string | Yes | 15-18 chars, alphanumeric | Salesforce Claim record ID |
| `documentId` | string | Yes | 15-18 chars, alphanumeric | Salesforce ContentDocument ID |
| `forceRefresh` | boolean | No | Default: `true` | Force fresh processing |

### 6.2 DocumentSplitResponse

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `claimId` | string | Yes | Salesforce Claim record ID |
| `sourceContentDocumentId` | string | Yes | Original ContentDocument ID |
| `sourceContentVersionId` | string | Yes | Original ContentVersion ID |
| `originalFileName` | string | Yes | Original PDF file name |
| `originalSizeBytes` | integer | Yes | Original file size in bytes |
| `originalPageCount` | integer | Yes | Total pages in original PDF |
| `partCount` | integer | Yes | Number of parts created |
| `status` | string | Yes | `PENDING`, `IN_PROGRESS`, `COMPLETED`, or `FAILED` |
| `dryRun` | boolean | Yes | Whether this was a dry run |
| `parts` | array | Yes | Array of PartDetail objects |
| `correlationId` | string | Yes | Request correlation ID (UUID) |
| `timestamp` | datetime | Yes | Operation timestamp (ISO 8601) |

### 6.3 PartDetail

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `partNumber` | integer | Yes | Sequential part number (1-based) |
| `pageStart` | integer | Yes | First page number (1-based) |
| `pageEnd` | integer | Yes | Last page number (inclusive) |
| `pageCount` | integer | Yes | Total pages in this part |
| `sizeBytes` | integer | Yes | Part size in bytes |
| `sizeMb` | number | Yes | Part size in megabytes |
| `contentVersionId` | string | Yes | SF ContentVersion ID for this part |
| `contentDocumentId` | string | Yes | SF ContentDocument ID for this part |
| `contentDocumentLinkId` | string | Yes | SF ContentDocumentLink ID |
| `fileName` | string | Yes | Part file name |

### 6.4 ErrorResponse

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `errorCode` | string | Yes | Machine-readable error code |
| `errorMessage` | string | Yes | Error status (typically `FAILURE`) |
| `errorDescription` | string | No | Human-readable error description |
| `transactionId` | string | Yes | Correlation/Transaction ID for tracing |
| `timeStamp` | datetime | Yes | Error timestamp (ISO 8601) |

### 6.5 HealthResponse

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | string | Yes | Service status (`UP` or `DOWN`) |
| `timestamp` | datetime | Yes | Health check timestamp |
| `version` | string | Yes | API version |

---

## 7. Error Handling

### Standard Error Format
All errors return JSON with consistent structure (see ErrorResponse model above).

### Error Code Catalog

| Error Code | HTTP Status | Description | Retryable |
|------------|-------------|-------------|-----------|
| `BAD_REQUEST` | 400 | Missing or invalid request parameters | No |
| `VALIDATION_ERROR` | 400 | Request body validation failed | No |
| `UNAUTHORIZED` | 401 | Missing/invalid client credentials | No |
| `NOT_FOUND` | 404 | Claim or document not found | No |
| `METHOD_NOT_ALLOWED` | 405 | Invalid HTTP method | No |
| `NOT_ACCEPTABLE` | 406 | Invalid Accept header | No |
| `UNSUPPORTED_MEDIA_TYPE` | 415 | Invalid Content-Type | No |
| `INTERNAL_ERROR` | 500 | Unexpected server error | Yes |
| `NOT_IMPLEMENTED` | 501 | Feature not implemented | No |
| `SYSTEM_API_ERROR` | 502 | System API error or timeout | Yes |

### Retry Guidance
- **Retryable errors (5xx):** Wait 5-10 seconds, then retry with exponential backoff
- **Non-retryable errors (4xx):** Fix the request before retrying
- **502 errors:** May indicate System API timeout — consider increasing client timeout or retrying later

---

## 8. Security Considerations

### PII Handling
- No PII is stored in API logs
- Salesforce record IDs are not considered PII

### Masking Rules
- Client secrets are never logged
- Sensitive data is masked in JSON logs

### Transport Security
- HTTPS only (HTTP not supported)
- TLS 1.2+ required

### Input Validation
- Salesforce IDs are validated against pattern `^[a-zA-Z0-9]{15,18}$`
- Request body is validated against RAML schema
- Invalid requests are rejected before reaching the System API

---

## 9. Dependencies

### Downstream System API
This EXP API proxies requests to the **SF Doc Split System API**.

| Property | Value |
|----------|-------|
| Base Path | `/sys/sf-doc-split/v1` |
| Protocol | HTTPS |
| Timeout | 120 seconds |
| Retry Attempts | 2 |
| Retry Frequency | 2000ms |

### System API Endpoint Called
```
POST /sys/sf-doc-split/v1/claims/{claimId}/documents/{documentId}/split?forceRefresh={true|false}
```

---

## 10. Change Log

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0.0 | TBD | Initial release | TBD |

---

## 11. Appendix — cURL Examples

### Health Check
```bash
curl -X GET "https://<BASE_URL>/api/healthcheck"
```

### Split Document (Basic)
```bash
curl -X POST "https://<BASE_URL>/api/documents/split" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-ID: 550e8400-e29b-41d4-a716-446655440000" \
  -d '{
    "claimId": "0ZkVA000000Ubyn0AC",
    "documentId": "069VA00000CB2CTYA1",
    "forceRefresh": true
  }'
```

### Split Document (Minimal Request)
```bash
curl -X POST "https://<BASE_URL>/api/documents/split" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{
    "claimId": "0ZkVA000000Ubyn0AC",
    "documentId": "069VA00000CB2CTYA1"
  }'
```

### Split Document (Use Cached Result)
```bash
curl -X POST "https://<BASE_URL>/api/documents/split" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{
    "claimId": "0ZkVA000000Ubyn0AC",
    "documentId": "069VA00000CB2CTYA1",
    "forceRefresh": false
  }'
```

### Split Document (With Custom Correlation ID)
```bash
curl -X POST "https://<BASE_URL>/api/documents/split" \
  -H "client_id: <CLIENT_ID>" \
  -H "client_secret: <CLIENT_SECRET>" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-ID: my-custom-trace-id-12345" \
  -d '{
    "claimId": "0ZkVA000000Ubyn0AC",
    "documentId": "069VA00000CB2CTYA1",
    "forceRefresh": true
  }'
```

---

## Items Marked TBD

The following items need to be provided to complete this documentation:

1. **Environment URLs:** DEV and PROD CloudHub base URLs
2. **Credential Process:** How to request client_id/client_secret
3. **API Policies:** Rate limiting, spike control, IP allowlist details (if any)
4. **Change Log:** Version dates and author information
