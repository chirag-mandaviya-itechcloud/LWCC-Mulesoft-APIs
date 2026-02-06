# Operational Runbook

## Salesforce PDF Split System API

---

## Table of Contents

1. [Service Overview](#service-overview)
2. [Health Check](#health-check)
3. [Common Operations](#common-operations)
4. [Incident Response](#incident-response)
5. [Monitoring & Alerts](#monitoring--alerts)
6. [Troubleshooting Guide](#troubleshooting-guide)
7. [Maintenance Procedures](#maintenance-procedures)

---

## Service Overview

### Purpose
System API for splitting large PDF documents stored in Salesforce into sequential parts (≤15MB each, max 5 parts) and re-uploading them linked to the original claim.

### Architecture
- **Runtime:** Mule 4.x on CloudHub
- **Dependencies:** Salesforce (source/target), Object Store v2 (idempotency/jobs)
- **Authentication:** OAuth 2.0 Client Credentials

### Endpoints
| Method | Path | Description |
|--------|------|-------------|
| POST | `/claims/{claimId}/documents/{contentDocumentId}/split` | Synchronous split |
| POST | `/claims/{claimId}/documents/{contentDocumentId}/split-jobs` | Create async job |
| GET | `/split-jobs/{jobId}` | Get job status |

### Contact Information
| Role | Contact |
|------|---------|
| Development Team | integration-dev@lwcc.com |
| Operations | integration-ops@lwcc.com |
| On-Call | PagerDuty: sf-doc-split-api |

---

## Health Check

### API Health Endpoint
```bash
curl -X GET "https://api.lwcc.com/sys/sf-doc-split/v1/health" \
  -H "Authorization: Bearer ${TOKEN}"
```

### Component Health Verification

**1. Check Application Status (Runtime Manager)**
```
Anypoint Platform → Runtime Manager → Applications → sf-doc-split-sys-api
Status should be: STARTED
```

**2. Verify Salesforce Connectivity**
- Check recent logs for `SALESFORCE_AUTH_FAILURE` errors
- Verify Salesforce Connected App is active
- Confirm API limits are not exhausted

**3. Check Object Store**
```
Runtime Manager → Application → Object Store
- Verify store is accessible
- Check entry counts are within limits
```

**4. Check Worker Status**
```
Runtime Manager → Application → Logs
Search for: "Worker started" or "Application deployed"
```

---

## Common Operations

### Restart Application
```
1. Go to Runtime Manager → Applications
2. Select sf-doc-split-sys-api
3. Click "Restart"
4. Wait for status: STARTED
5. Verify health check passes
```

### Scale Workers
```
1. Go to Runtime Manager → Applications → sf-doc-split-sys-api
2. Click "Manage Application"
3. Adjust worker count/size
4. Click "Apply Changes"
```

**Recommended Settings:**
| Environment | Workers | Size |
|-------------|---------|------|
| DEV | 1 | 0.2 vCore |
| UAT | 2 | 0.2 vCore |
| PROD | 4 | 0.5 vCore |

### View Logs
```
1. Runtime Manager → Applications → sf-doc-split-sys-api
2. Click "Logs"
3. Filter by:
   - Level: ERROR, WARN, INFO
   - Search: correlationId value
```

### Check Job Status Manually
```bash
curl -X GET "https://api.lwcc.com/sys/sf-doc-split/v1/split-jobs/{jobId}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Correlation-Id: ${CORRELATION_ID}"
```

---

## Incident Response

### Scenario: High Error Rate Alert

**Symptoms:**
- Alert: "sf-doc-split error rate > 5%"
- Multiple 5xx responses in logs

**Investigation Steps:**
1. Check logs for specific error codes
   ```
   Filter: level:ERROR AND app:sf-doc-split-sys-api
   ```

2. Identify error pattern:
   - `SALESFORCE_AUTH_FAILURE` → Check SF credentials
   - `SALESFORCE_RATE_LIMIT` → Reduce concurrency
   - `SALESFORCE_UPSTREAM_ERROR` → Check SF status
   - `INTERNAL_ERROR` → Check worker memory/CPU

3. Check Salesforce Status:
   - Visit: https://status.salesforce.com
   - Check org-specific limits

**Resolution:**
| Error Pattern | Action |
|--------------|--------|
| SF Auth Failure | Rotate credentials in Secrets Manager |
| SF Rate Limit | Reduce worker concurrency temporarily |
| SF Upstream Error | Wait for SF recovery, retry failed jobs |
| Internal Error | Restart application, check logs |

---

### Scenario: Job Queue Backlog

**Symptoms:**
- Alert: "Pending jobs > 10 for >5 minutes"
- Jobs stuck in ACCEPTED or VALIDATING state

**Investigation Steps:**
1. Check Object Store for job count:
   ```
   Runtime Manager → Object Store → split-jobs partition
   ```

2. Verify workers are consuming:
   ```
   Search logs: "Processing job" OR "Job completed"
   ```

3. Check for stuck processes:
   ```
   Search logs: "timeout" OR "hung" OR "deadlock"
   ```

**Resolution:**
1. If workers are stuck:
   - Restart application
   - Check SF connectivity

2. If backlog is growing:
   - Increase worker count temporarily
   - Consider throttling incoming requests

3. For stuck jobs:
   - Jobs will timeout and mark as FAILED
   - Clients can retry failed jobs

---

### Scenario: Salesforce Rate Limit Exceeded

**Symptoms:**
- `SALESFORCE_RATE_LIMIT` errors in logs
- HTTP 429 responses

**Investigation Steps:**
1. Check Salesforce API Usage:
   ```
   Setup → System Overview → API Usage (Last 24 Hours)
   ```

2. Identify consumption pattern:
   - Check concurrent job count
   - Review split frequency

**Resolution:**
1. Immediate:
   - Reduce worker concurrency in config
   - Wait for rate limit reset (typically 24h rolling)

2. Long-term:
   - Implement request throttling
   - Optimize Salesforce API calls
   - Consider Salesforce API limit increase request

---

### Scenario: Manual Cleanup Required

**Symptoms:**
- Failed jobs left orphaned ContentDocuments
- Alert from orphan detection job

**Investigation Steps:**
1. Query Salesforce for orphaned parts:
   ```sql
   SELECT Id, Title, CreatedDate, CreatedById
   FROM ContentDocument
   WHERE Title LIKE '%_part0%.pdf'
   AND CreatedDate > LAST_N_DAYS:1
   ORDER BY CreatedDate DESC
   ```

2. Cross-reference with job store:
   - Check Object Store for FAILED jobs
   - Match correlationIds

**Resolution:**
1. Export list of orphaned IDs
2. Verify these are actually orphans (not linked to claims)
3. Delete via Salesforce Data Loader or API:
   ```bash
   sfdx force:data:record:delete -s ContentDocument -i 069Hp00000XXXXAAA
   ```
4. Log cleanup action with correlation IDs

---

## Monitoring & Alerts

### Key Metrics

| Metric | Description | Threshold |
|--------|-------------|-----------|
| Request Rate | Requests per minute | Baseline ± 50% |
| Error Rate | % of 5xx responses | > 5% |
| P95 Latency | 95th percentile response time | > 120s |
| Active Jobs | Jobs in progress | > 10 |
| SF API Calls | Calls to Salesforce per minute | < 80% of limit |

### Alert Configuration

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| High Error Rate | Error rate > 5% for 5 min | Warning | Investigate logs |
| SF Rate Limit | Any 429 in 5 min | Warning | Check SF usage |
| SF Auth Failure | Any auth failure | Critical | Rotate credentials |
| Processing Timeout | > 3 timeouts in 15 min | Warning | Check SF/workers |
| Job Backlog | Pending > 10 for 5 min | Warning | Scale workers |
| Worker Down | Health check fails | Critical | Restart app |

### Dashboard Widgets

1. **Request Volume** - Requests/minute by endpoint
2. **Error Distribution** - Pie chart by error code
3. **Latency** - P50, P90, P95, P99
4. **SF API Usage** - Calls/minute
5. **Active Jobs** - Gauge showing in-progress
6. **Part Creation** - Parts uploaded/minute

---

## Troubleshooting Guide

### Log Search Patterns

**Find all logs for a request:**
```
correlationId:"550e8400-e29b-41d4-a716-446655440000"
```

**Find all errors:**
```
level:ERROR AND app:sf-doc-split-sys-api
```

**Find Salesforce errors:**
```
errorCode:SALESFORCE_* AND app:sf-doc-split-sys-api
```

**Find failed jobs:**
```
event:JOB_FAILED AND app:sf-doc-split-sys-api
```

### Common Issues

| Symptom | Possible Cause | Solution |
|---------|----------------|----------|
| All requests return 401 | OAuth token validation failing | Check API Manager policy, token endpoint |
| All requests return 502 | SF connectivity issue | Check SF status, credentials |
| Slow response times | Large PDF, SF throttling | Use async endpoint, check SF limits |
| Jobs stuck in ACCEPTED | Worker not consuming queue | Restart app, check VM queue |
| Parts not linking to claim | ContentDocumentLink creation failing | Check SF permissions, share settings |

### Debug Mode

To enable debug logging temporarily:
1. Runtime Manager → Application → Settings
2. Add property: `logging.level=DEBUG`
3. Apply changes (causes restart)
4. Collect logs
5. Revert to `logging.level=INFO`

---

## Maintenance Procedures

### Scheduled Maintenance Window

**When:** Saturdays 02:00-04:00 IST (low traffic period)

**Pre-maintenance:**
1. Notify stakeholders 24 hours in advance
2. Verify no critical jobs in progress
3. Export current configuration

**During maintenance:**
1. Apply updates via Runtime Manager
2. Verify deployment successful
3. Run smoke tests

**Post-maintenance:**
1. Verify health checks pass
2. Monitor for 30 minutes
3. Send completion notice

### Credential Rotation

**Frequency:** Every 90 days

**Procedure:**
1. Generate new Salesforce Connected App credentials
2. Add new credentials to Secrets Manager (don't remove old yet)
3. Update application to use new credentials
4. Verify connectivity
5. Remove old credentials from Secrets Manager

### Disaster Recovery

**RPO:** 0 (no data loss - all data in Salesforce)
**RTO:** 15 minutes

**Recovery Procedure:**
1. Deploy application to alternate region
2. Update DNS/load balancer
3. Verify connectivity to Salesforce
4. Resume operations

### Rollback Procedure

1. Go to Runtime Manager → Applications
2. Select sf-doc-split-sys-api
3. Click "Manage Application"
4. Under "Runtime", select previous version
5. Click "Apply Changes"
6. Monitor logs for 15 minutes
7. Notify stakeholders

---

## Appendix

### Environment URLs

| Environment | API URL | Runtime Manager |
|-------------|---------|-----------------|
| DEV | https://api-dev.lwcc.com/sys/sf-doc-split/v1 | anypoint.mulesoft.com |
| UAT | https://api-uat.lwcc.com/sys/sf-doc-split/v1 | anypoint.mulesoft.com |
| PROD | https://api.lwcc.com/sys/sf-doc-split/v1 | anypoint.mulesoft.com |

### Useful Commands

**Get OAuth Token:**
```bash
curl -X POST "https://auth.lwcc.com/oauth2/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=sf-doc-split:write"
```

**Test Split (Dry Run):**
```bash
curl -X POST "https://api.lwcc.com/sys/sf-doc-split/v1/claims/${CLAIM_ID}/documents/${DOC_ID}/split?dryRun=true" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Correlation-Id: $(uuidgen)"
```

**Check Job Status:**
```bash
curl -X GET "https://api.lwcc.com/sys/sf-doc-split/v1/split-jobs/${JOB_ID}" \
  -H "Authorization: Bearer ${TOKEN}"
```
