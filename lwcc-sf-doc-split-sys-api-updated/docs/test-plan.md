# Test Plan

## Salesforce PDF Split System API

---

## Table of Contents

1. [Test Strategy](#test-strategy)
2. [Test Environment](#test-environment)
3. [Test Data Requirements](#test-data-requirements)
4. [Functional Test Cases](#functional-test-cases)
5. [Error Handling Test Cases](#error-handling-test-cases)
6. [Performance Test Scenarios](#performance-test-scenarios)
7. [Security Test Cases](#security-test-cases)
8. [Integration Test Cases](#integration-test-cases)

---

## Test Strategy

### Testing Levels

| Level | Scope | Approach |
|-------|-------|----------|
| Unit | Individual components | Mocked dependencies |
| Integration | End-to-end flows | Salesforce sandbox |
| Performance | Load and stress | Synthetic data, monitored |
| Security | AuthN/AuthZ, data protection | Penetration testing |

### Entry Criteria
- API spec approved
- Test environment configured
- Test data prepared in Salesforce sandbox

### Exit Criteria
- All P1 test cases pass
- No critical/high defects open
- Performance benchmarks met
- Security scan passed

---

## Test Environment

### Salesforce Sandbox
- **Org:** lwcc--test.sandbox.my.salesforce.com
- **Connected App:** sf-doc-split-test-app

### API Gateway
- **URL:** https://api-test.lwcc.com/sys/sf-doc-split/v1

### Test Tools
- Postman / Newman (API testing)
- JMeter (Performance testing)
- MUnit (Unit testing)

---

## Test Data Requirements

### Test Claims

| Claim ID | Description |
|----------|-------------|
| a0B5g00000TEST001 | Standard claim with multiple documents |
| a0B5g00000TEST002 | Claim with no documents |
| a0B5g00000TEST003 | Claim with large documents |

### Test PDFs

| ID | Name | Size | Pages | Purpose |
|----|------|------|-------|---------|
| DOC001 | SmallDoc.pdf | 5 MB | 20 | Single part result |
| DOC002 | MediumDoc.pdf | 25 MB | 80 | Two parts |
| DOC003 | LargeDoc.pdf | 45 MB | 150 | 3-4 parts |
| DOC004 | MaxDoc.pdf | 75 MB | 250 | 5 parts (max) |
| DOC005 | OversizedDoc.pdf | 90 MB | 300 | Exceeds policy |
| DOC006 | HugePageDoc.pdf | 30 MB | 10 | Single page > 15MB |
| DOC007 | CorruptDoc.pdf | 10 MB | - | Corrupted PDF |
| DOC008 | NotAPdf.docx | 2 MB | - | Wrong file type |
| DOC009 | EncryptedDoc.pdf | 15 MB | 50 | Password protected |
| DOC010 | EmptyDoc.pdf | 1 KB | 0 | Zero pages |

---

## Functional Test Cases

### TC-001: Small PDF - Single Part
**Priority:** P1
**Endpoint:** POST /claims/{claimId}/documents/{contentDocumentId}/split

| Field | Value |
|-------|-------|
| **Precondition** | DOC001 (5MB, 20 pages) linked to TEST001 |
| **Input** | claimId=a0B5g00000TEST001, contentDocumentId=069xxx001 |
| **Expected Result** | 200 OK, partCount=1, all pages in single part |
| **Validation** | - Part size < 15MB<br>- pageStart=1, pageEnd=20<br>- ContentVersion created in SF<br>- ContentDocumentLink created |

---

### TC-002: Medium PDF - Two Parts
**Priority:** P1
**Endpoint:** POST /claims/{claimId}/documents/{contentDocumentId}/split

| Field | Value |
|-------|-------|
| **Precondition** | DOC002 (25MB, 80 pages) linked to TEST001 |
| **Input** | claimId=a0B5g00000TEST001, contentDocumentId=069xxx002 |
| **Expected Result** | 200 OK, partCount=2 |
| **Validation** | - Each part ≤ 15MB<br>- Part 1: pages 1-N, Part 2: pages N+1-80<br>- Page order preserved<br>- Both parts linked to claim |

---

### TC-003: Large PDF - Three to Four Parts
**Priority:** P1
**Endpoint:** POST /claims/{claimId}/documents/{contentDocumentId}/split

| Field | Value |
|-------|-------|
| **Precondition** | DOC003 (45MB, 150 pages) linked to TEST001 |
| **Input** | claimId=a0B5g00000TEST001, contentDocumentId=069xxx003 |
| **Expected Result** | 200 OK, partCount=3 or 4 |
| **Validation** | - Each part ≤ 15MB<br>- Page sequence continuous<br>- All parts linked to claim |

---

### TC-004: Maximum Size PDF - Five Parts
**Priority:** P1
**Endpoint:** POST /claims/{claimId}/documents/{contentDocumentId}/split

| Field | Value |
|-------|-------|
| **Precondition** | DOC004 (75MB, 250 pages) linked to TEST001 |
| **Input** | claimId=a0B5g00000TEST001, contentDocumentId=069xxx004 |
| **Expected Result** | 200 OK, partCount=5 |
| **Validation** | - Each part ≤ 15MB<br>- Exactly 5 parts<br>- All pages accounted for |

---

### TC-005: Dry Run Mode
**Priority:** P1
**Endpoint:** POST /claims/{claimId}/documents/{contentDocumentId}/split?dryRun=true

| Field | Value |
|-------|-------|
| **Precondition** | DOC003 linked to TEST001 |
| **Input** | claimId=a0B5g00000TEST001, contentDocumentId=069xxx003, dryRun=true |
| **Expected Result** | 200 OK, status="DRY_RUN" |
| **Validation** | - Split plan returned<br>- contentVersionId/contentDocumentId are null<br>- No files created in Salesforce |

---

### TC-006: Custom maxPartSizeMb
**Priority:** P2
**Endpoint:** POST /claims/{claimId}/documents/{contentDocumentId}/split?maxPartSizeMb=10

| Field | Value |
|-------|-------|
| **Precondition** | DOC002 (25MB) linked to TEST001 |
| **Input** | maxPartSizeMb=10 |
| **Expected Result** | 200 OK, partCount=3 |
| **Validation** | - Each part ≤ 10MB<br>- More parts than default |

---

### TC-007: Custom maxParts
**Priority:** P2
**Endpoint:** POST /claims/{claimId}/documents/{contentDocumentId}/split?maxParts=3

| Field | Value |
|-------|-------|
| **Precondition** | DOC004 (75MB) linked to TEST001 |
| **Input** | maxParts=3 |
| **Expected Result** | 422 PDF_TOO_LARGE_FOR_POLICY |
| **Validation** | - Error returned because 75MB needs >3 parts |

---

### TC-008: Async Job Creation
**Priority:** P1
**Endpoint:** POST /claims/{claimId}/documents/{contentDocumentId}/split-jobs

| Field | Value |
|-------|-------|
| **Precondition** | DOC003 linked to TEST001 |
| **Input** | claimId=a0B5g00000TEST001, contentDocumentId=069xxx003 |
| **Expected Result** | 202 Accepted |
| **Validation** | - jobId returned<br>- Location header set<br>- status="ACCEPTED" |

---

### TC-009: Job Status - Processing
**Priority:** P1
**Endpoint:** GET /split-jobs/{jobId}

| Field | Value |
|-------|-------|
| **Precondition** | Job created and in progress |
| **Input** | jobId from TC-008 |
| **Expected Result** | 200 OK, status in [VALIDATING, DOWNLOADING, SPLITTING, UPLOADING] |
| **Validation** | - progress object present<br>- percentComplete between 0-99 |

---

### TC-010: Job Status - Completed
**Priority:** P1
**Endpoint:** GET /split-jobs/{jobId}

| Field | Value |
|-------|-------|
| **Precondition** | Job completed successfully |
| **Input** | jobId from completed job |
| **Expected Result** | 200 OK, status="COMPLETED" |
| **Validation** | - result object present<br>- Contains all part details<br>- completedAt timestamp set |

---

### TC-011: Idempotency - Same Request
**Priority:** P1
**Endpoint:** POST /claims/{claimId}/documents/{contentDocumentId}/split

| Field | Value |
|-------|-------|
| **Precondition** | TC-001 completed successfully |
| **Input** | Same claimId and contentDocumentId as TC-001 |
| **Expected Result** | 200 OK with cached result |
| **Validation** | - Same part IDs returned<br>- No new files created in SF<br>- Response matches original |

---

### TC-012: Idempotency - New Version
**Priority:** P2
**Endpoint:** POST /claims/{claimId}/documents/{contentDocumentId}/split

| Field | Value |
|-------|-------|
| **Precondition** | TC-001 completed, then source doc updated in SF |
| **Input** | Same claimId and contentDocumentId |
| **Expected Result** | 200 OK with new split |
| **Validation** | - New parts created<br>- Different contentVersionIds<br>- New split performed |

---

## Error Handling Test Cases

### TC-E01: PDF Too Large for Policy
**Priority:** P1

| Field | Value |
|-------|-------|
| **Precondition** | DOC005 (90MB) linked to TEST001 |
| **Input** | claimId=a0B5g00000TEST001, contentDocumentId=069xxx005 |
| **Expected Result** | 422 PDF_TOO_LARGE_FOR_POLICY |
| **Validation** | - Error response with details<br>- requiredParts > 5<br>- No files created |

---

### TC-E02: Single Page Exceeds Limit
**Priority:** P1

| Field | Value |
|-------|-------|
| **Precondition** | DOC006 (has 18MB page) linked to TEST001 |
| **Input** | claimId=a0B5g00000TEST001, contentDocumentId=069xxx006 |
| **Expected Result** | 422 SINGLE_PAGE_EXCEEDS_LIMIT |
| **Validation** | - Error includes pageNumber<br>- pageSizeBytes shown<br>- No files created |

---

### TC-E03: Corrupt PDF
**Priority:** P1

| Field | Value |
|-------|-------|
| **Precondition** | DOC007 (corrupt) linked to TEST001 |
| **Input** | claimId=a0B5g00000TEST001, contentDocumentId=069xxx007 |
| **Expected Result** | 422 INVALID_PDF |
| **Validation** | - Clear error message<br>- No partial files created |

---

### TC-E04: Not a PDF
**Priority:** P1

| Field | Value |
|-------|-------|
| **Precondition** | DOC008 (DOCX file) linked to TEST001 |
| **Input** | claimId=a0B5g00000TEST001, contentDocumentId=069xxx008 |
| **Expected Result** | 422 NOT_A_PDF |
| **Validation** | - detectedMimeType in response |

---

### TC-E05: Document Not Linked to Claim
**Priority:** P1

| Field | Value |
|-------|-------|
| **Precondition** | DOC001 linked to TEST001 (not TEST002) |
| **Input** | claimId=a0B5g00000TEST002, contentDocumentId=069xxx001 |
| **Expected Result** | 409 DOCUMENT_NOT_LINKED_TO_CLAIM |
| **Validation** | - claimId and contentDocumentId in details |

---

### TC-E06: Claim Not Found
**Priority:** P1

| Field | Value |
|-------|-------|
| **Input** | claimId=a0B5g00000INVALID, contentDocumentId=069xxx001 |
| **Expected Result** | 404 CLAIM_NOT_FOUND |

---

### TC-E07: Document Not Found
**Priority:** P1

| Field | Value |
|-------|-------|
| **Input** | claimId=a0B5g00000TEST001, contentDocumentId=069INVALID123 |
| **Expected Result** | 404 DOCUMENT_NOT_FOUND |

---

### TC-E08: Invalid claimId Format
**Priority:** P2

| Field | Value |
|-------|-------|
| **Input** | claimId=invalid-format |
| **Expected Result** | 400 VALIDATION_ERROR |
| **Validation** | - Field name in error<br>- Expected pattern shown |

---

### TC-E09: Missing Authorization
**Priority:** P1

| Field | Value |
|-------|-------|
| **Input** | No Authorization header |
| **Expected Result** | 401 UNAUTHORIZED |

---

### TC-E10: Insufficient Scope
**Priority:** P2

| Field | Value |
|-------|-------|
| **Precondition** | Token with only sf-doc-split:read scope |
| **Input** | POST request with read-only token |
| **Expected Result** | 403 FORBIDDEN |

---

### TC-E11: Salesforce Rate Limit
**Priority:** P2

| Field | Value |
|-------|-------|
| **Setup** | Exhaust SF API limits or mock 429 |
| **Expected Result** | 429 SALESFORCE_RATE_LIMIT |
| **Validation** | - Retry-After header present<br>- retryable=true |

---

### TC-E12: Partial Upload Failure - Rollback
**Priority:** P1

| Field | Value |
|-------|-------|
| **Setup** | Simulate failure on part 3 upload |
| **Expected Result** | Error returned, parts 1-2 cleaned up |
| **Validation** | - No orphaned files in SF<br>- Job marked as FAILED |

---

### TC-E13: Job Not Found
**Priority:** P2

| Field | Value |
|-------|-------|
| **Input** | GET /split-jobs/job_invalid-uuid-here |
| **Expected Result** | 404 Job not found |

---

### TC-E14: Password Protected PDF
**Priority:** P2

| Field | Value |
|-------|-------|
| **Precondition** | DOC009 (encrypted) linked to TEST001 |
| **Expected Result** | 422 INVALID_PDF |
| **Validation** | - Reason indicates encryption/password |

---

### TC-E15: Empty PDF
**Priority:** P3

| Field | Value |
|-------|-------|
| **Precondition** | DOC010 (0 pages) linked to TEST001 |
| **Expected Result** | 422 INVALID_PDF |

---

## Performance Test Scenarios

### PT-001: Baseline Load
**Objective:** Establish baseline performance

| Parameter | Value |
|-----------|-------|
| Load | 5 requests/minute |
| Duration | 30 minutes |
| Document Size | Mix of 10-50MB |

**Success Criteria:**
- P95 latency < 60 seconds
- Error rate < 1%
- No memory leaks

---

### PT-002: Peak Load
**Objective:** Validate under peak conditions

| Parameter | Value |
|-----------|-------|
| Load | 20 requests/minute |
| Duration | 15 minutes |
| Document Size | Mix of 10-50MB |

**Success Criteria:**
- P95 latency < 120 seconds
- Error rate < 5%
- Graceful degradation (no crashes)

---

### PT-003: Large File Processing
**Objective:** Validate memory handling for max-size files

| Parameter | Value |
|-----------|-------|
| Load | 10 concurrent 75MB files |
| Duration | 30 minutes |

**Success Criteria:**
- All files processed successfully
- No OutOfMemory errors
- Worker memory stable

---

### PT-004: Sustained Load
**Objective:** Check for degradation over time

| Parameter | Value |
|-----------|-------|
| Load | 10 requests/minute |
| Duration | 2 hours |

**Success Criteria:**
- Consistent response times
- No memory growth
- No connection leaks

---

## Security Test Cases

### ST-001: Authentication Required
- Verify all endpoints require valid OAuth token
- Verify invalid tokens are rejected

### ST-002: Authorization Scopes
- Verify sf-doc-split:write required for POST
- Verify sf-doc-split:read sufficient for GET

### ST-003: Input Validation
- SQL injection attempts in IDs
- XSS attempts in parameters
- Path traversal attempts

### ST-004: Data Exposure
- Verify no sensitive data in error messages
- Verify no credentials in logs
- Verify ID masking in logs

### ST-005: Rate Limiting
- Verify API Manager rate limits enforced
- Verify graceful handling of limit exceeded

---

## Integration Test Cases

### IT-001: End-to-End Sync Split
Complete flow from request to Salesforce verification

### IT-002: End-to-End Async Split
Complete flow including job polling

### IT-003: Salesforce Connectivity Recovery
Verify behavior when SF temporarily unavailable

### IT-004: Object Store Failover
Verify idempotency behavior during Object Store issues

---

## Test Execution Schedule

| Phase | Tests | Duration |
|-------|-------|----------|
| Unit Testing | MUnit tests | 1 day |
| Integration Testing | TC-001 to TC-012, TC-E01 to TC-E15 | 3 days |
| Performance Testing | PT-001 to PT-004 | 2 days |
| Security Testing | ST-001 to ST-005 | 1 day |
| UAT | Selected scenarios | 2 days |

---

## Defect Severity Definitions

| Severity | Definition | Example |
|----------|------------|---------|
| Critical | System unusable | API returns 500 for all requests |
| High | Major function broken | Split creates wrong number of parts |
| Medium | Function impaired | Dry run mode not working |
| Low | Minor issue | Wrong error message text |
