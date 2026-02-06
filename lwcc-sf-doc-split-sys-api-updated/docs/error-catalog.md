# Error Catalog

## Salesforce PDF Split System API

This document provides a complete reference for all error codes returned by the API.

---

## Error Response Schema

All errors follow this consistent structure:

```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "ERROR_CODE_HERE",
  "message": "Human-readable error message",
  "details": { },
  "retryable": false
}
```

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | ISO 8601 datetime | When the error occurred (Asia/Kolkata timezone) |
| `correlationId` | UUID | Unique identifier for request tracing |
| `errorCode` | String | Machine-readable error code |
| `message` | String | Human-readable message (safe for display) |
| `details` | Object | Additional context (optional, non-sensitive) |
| `retryable` | Boolean | Whether the request can be retried |

---

## Error Codes Reference

### Client Errors (4xx)

#### VALIDATION_ERROR
**HTTP Status:** 400 Bad Request
**Retryable:** No

Invalid input parameters provided in the request.

**Common Causes:**
- Invalid claimId format (not 15 or 18 characters)
- Invalid contentDocumentId format (doesn't start with 069)
- Invalid jobId format
- Query parameter out of range

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "VALIDATION_ERROR",
  "message": "Invalid claimId format - must be 15 or 18 character Salesforce ID",
  "details": {
    "field": "claimId",
    "providedValue": "invalid-claim-id",
    "expectedPattern": "^[a-zA-Z0-9]{15}|[a-zA-Z0-9]{18}$"
  },
  "retryable": false
}
```

---

#### UNAUTHORIZED
**HTTP Status:** 401 Unauthorized
**Retryable:** No

Missing or invalid authentication credentials.

**Common Causes:**
- Missing Authorization header
- Invalid or expired OAuth token
- Malformed bearer token

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "UNAUTHORIZED",
  "message": "Valid OAuth 2.0 bearer token required",
  "details": {
    "hint": "Include Authorization header with valid bearer token"
  },
  "retryable": false
}
```

---

#### FORBIDDEN
**HTTP Status:** 403 Forbidden
**Retryable:** No

Caller lacks required permissions or scopes.

**Common Causes:**
- Token missing required scope (sf-doc-split:write)
- Caller not authorized for the specific claim

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "FORBIDDEN",
  "message": "Caller does not have sf-doc-split:write scope",
  "details": {
    "requiredScope": "sf-doc-split:write",
    "providedScopes": ["sf-doc-split:read"]
  },
  "retryable": false
}
```

---

#### CLAIM_NOT_FOUND
**HTTP Status:** 404 Not Found
**Retryable:** No

The specified claim record does not exist in Salesforce.

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "CLAIM_NOT_FOUND",
  "message": "Claim record not found in Salesforce",
  "details": {
    "claimId": "a0B5g00000XXXXAAA"
  },
  "retryable": false
}
```

---

#### DOCUMENT_NOT_FOUND
**HTTP Status:** 404 Not Found
**Retryable:** No

The specified ContentDocument does not exist in Salesforce.

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "DOCUMENT_NOT_FOUND",
  "message": "Content document not found in Salesforce",
  "details": {
    "contentDocumentId": "069Hp00000YYYYBBB"
  },
  "retryable": false
}
```

---

#### DOCUMENT_NOT_LINKED_TO_CLAIM
**HTTP Status:** 409 Conflict
**Retryable:** No

The document exists but is not linked to the specified claim.

**Resolution:** Verify the document is associated with the claim via ContentDocumentLink in Salesforce.

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "DOCUMENT_NOT_LINKED_TO_CLAIM",
  "message": "The specified document is not linked to this claim",
  "details": {
    "claimId": "a0B5g00000XXXXAAA",
    "contentDocumentId": "069Hp00000YYYYBBB",
    "hint": "Verify the document is associated with the claim via ContentDocumentLink"
  },
  "retryable": false
}
```

---

#### NOT_A_PDF
**HTTP Status:** 422 Unprocessable Entity
**Retryable:** No

The document is not a PDF file.

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "NOT_A_PDF",
  "message": "Document is not a PDF file",
  "details": {
    "detectedFileExtension": "docx",
    "detectedContentType": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "hint": "Only PDF documents can be split"
  },
  "retryable": false
}
```

---

#### INVALID_PDF
**HTTP Status:** 422 Unprocessable Entity
**Retryable:** No

The PDF is corrupted, encrypted, or cannot be processed.

**Common Causes:**
- Corrupted PDF file
- Password-protected PDF
- Encrypted PDF
- Unsupported PDF version

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "INVALID_PDF",
  "message": "PDF file is corrupted or cannot be processed",
  "details": {
    "reason": "Unable to parse PDF structure - file may be corrupted, encrypted, or password-protected"
  },
  "retryable": false
}
```

---

#### PDF_TOO_LARGE_FOR_POLICY
**HTTP Status:** 422 Unprocessable Entity
**Retryable:** No

The PDF requires more than 5 parts to satisfy the 15MB size constraint.

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "PDF_TOO_LARGE_FOR_POLICY",
  "message": "PDF requires more than 5 parts to satisfy the 15MB size constraint",
  "details": {
    "originalSizeBytes": 89128960,
    "originalSizeMb": 85.02,
    "originalPageCount": 312,
    "requiredParts": 7,
    "maxAllowedParts": 5,
    "maxPartSizeMb": 15
  },
  "retryable": false
}
```

---

#### SINGLE_PAGE_EXCEEDS_LIMIT
**HTTP Status:** 422 Unprocessable Entity
**Retryable:** No

A single page in the PDF exceeds the maximum part size (15MB).

**Common Causes:**
- High-resolution images embedded in the page
- Large vector graphics
- Scanned document with high DPI

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "SINGLE_PAGE_EXCEEDS_LIMIT",
  "message": "A single page in the PDF exceeds the maximum part size of 15MB",
  "details": {
    "pageNumber": 47,
    "pageSizeBytes": 18874368,
    "pageSizeMb": 18.0,
    "maxPartSizeBytes": 15728640,
    "maxPartSizeMb": 15,
    "hint": "The PDF contains high-resolution images that cannot be split at page boundaries"
  },
  "retryable": false
}
```

---

#### SALESFORCE_RATE_LIMIT
**HTTP Status:** 429 Too Many Requests
**Retryable:** Yes

Salesforce API rate limit has been exceeded.

**Resolution:** Wait for the period specified in `Retry-After` header before retrying.

**Response Headers:**
- `Retry-After: 60` (seconds to wait)

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "SALESFORCE_RATE_LIMIT",
  "message": "Salesforce API rate limit exceeded",
  "details": {
    "retryAfterSeconds": 60,
    "hint": "Request has been throttled - retry after the specified interval"
  },
  "retryable": true
}
```

---

### Server Errors (5xx)

#### SALESFORCE_AUTH_FAILURE
**HTTP Status:** 502 Bad Gateway
**Retryable:** Yes

Failed to authenticate with Salesforce.

**Common Causes:**
- Salesforce credentials expired
- Connected App revoked
- Salesforce service unavailable

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "SALESFORCE_AUTH_FAILURE",
  "message": "Failed to authenticate with Salesforce",
  "details": {
    "hint": "Salesforce credentials may have expired or been revoked"
  },
  "retryable": true
}
```

---

#### SALESFORCE_UPSTREAM_ERROR
**HTTP Status:** 502 Bad Gateway
**Retryable:** Yes

Salesforce returned an unexpected error.

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "SALESFORCE_UPSTREAM_ERROR",
  "message": "Salesforce returned an unexpected error",
  "details": {
    "operation": "ContentVersion.create",
    "sfErrorCode": "STORAGE_LIMIT_EXCEEDED"
  },
  "retryable": true
}
```

---

#### PROCESSING_TIMEOUT
**HTTP Status:** 504 Gateway Timeout
**Retryable:** Yes

Request processing exceeded the maximum allowed time.

**Resolution:** Use the async endpoint for large documents.

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "PROCESSING_TIMEOUT",
  "message": "Request processing exceeded the maximum allowed time",
  "details": {
    "timeoutMs": 300000,
    "lastCompletedStep": "UPLOADING",
    "hint": "Use the async endpoint for large documents"
  },
  "retryable": true
}
```

---

#### INTERNAL_ERROR
**HTTP Status:** 500 Internal Server Error
**Retryable:** Yes

An unexpected internal error occurred.

**Resolution:** Retry the request. If the error persists, contact support with the correlation ID.

**Example Response:**
```json
{
  "timestamp": "2026-01-20T14:35:22+05:30",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "errorCode": "INTERNAL_ERROR",
  "message": "An unexpected error occurred during processing",
  "details": {
    "hint": "Please retry the request or contact support with the correlation ID"
  },
  "retryable": true
}
```

---

## Error Code Summary Table

| Error Code | HTTP Status | Retryable | Description |
|------------|-------------|-----------|-------------|
| `VALIDATION_ERROR` | 400 | No | Invalid input parameters |
| `UNAUTHORIZED` | 401 | No | Missing or invalid authentication |
| `FORBIDDEN` | 403 | No | Insufficient permissions |
| `CLAIM_NOT_FOUND` | 404 | No | Claim record doesn't exist |
| `DOCUMENT_NOT_FOUND` | 404 | No | ContentDocument doesn't exist |
| `DOCUMENT_NOT_LINKED_TO_CLAIM` | 409 | No | Document not linked to claim |
| `NOT_A_PDF` | 422 | No | File is not a PDF |
| `INVALID_PDF` | 422 | No | PDF is corrupted/unreadable |
| `PDF_TOO_LARGE_FOR_POLICY` | 422 | No | Needs >5 parts |
| `SINGLE_PAGE_EXCEEDS_LIMIT` | 422 | No | One page >15MB |
| `SALESFORCE_RATE_LIMIT` | 429 | Yes | SF rate limit hit |
| `SALESFORCE_AUTH_FAILURE` | 502 | Yes | SF auth failed |
| `SALESFORCE_UPSTREAM_ERROR` | 502 | Yes | SF returned error |
| `PROCESSING_TIMEOUT` | 504 | Yes | Processing timed out |
| `INTERNAL_ERROR` | 500 | Yes | Unexpected error |
