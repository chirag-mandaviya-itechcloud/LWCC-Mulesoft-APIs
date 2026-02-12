@RestResource(urlMapping='/IDPSplitDocUploadCallback/*')
global with sharing class API_IDPSplitDocUploadCallback {
	@HttpPost
    global static CallbackResponse loadPayload() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String body = '';

        try {
            // Parse request body
            body = (req.requestBody == null)
                ? ''
                : req.requestBody.toString();

            System.debug('===== MULESOFT SPLIT CALLBACK RECEIVED =====');
            System.debug('Body: ' + body);

            // Validate body is not empty
            if (String.isBlank(body)) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                return errorResponse('Empty request body', 'ValidationError', null);
            }

            // Parse the callback payload
            Map<String, Object> payloadMap = (Map<String, Object>) JSON.deserializeUntyped(body);

            String claimId = (String) payloadMap.get('claimId');
           // String documentId = (String) payloadMap.get('documentId');         
            String documentId = (String) payloadMap.get('sourceContentDocumentId');
           
            String status = (String) payloadMap.get('status');

            System.debug('claimId: ' + claimId + ', documentId: ' + documentId + ', status: ' + status);

            // Validate required fields
            if (String.isBlank(claimId) || String.isBlank(documentId)) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                return errorResponse('Missing required fields: claimId and documentId', 'ValidationError', documentId);
            }

            // Handle FAILED status from MuleSoft
            if (status == 'FAILED') {
                String errorMsg = (String) payloadMap.get('errorMessage');
                System.debug(LoggingLevel.ERROR, 'MuleSoft split FAILED for document: ' + documentId + ' - ' + errorMsg);

                IntegrationLogManager.createIntegrationLog(
                    'API_SplitDocUploadCallback',
                    documentId + '_' + claimId,
                    claimId,
                    body,
                    null,
                    'Failed',
                    errorMsg
                );

                // send notification about the failure too
                sendBellNotification(documentId, claimId, 0, false);

                res.statusCode = 200;
                res.addHeader('Content-Type', 'application/json');
                return errorResponse('Split operation failed: ' + errorMsg, 'SplitFailure', documentId);
            }

            // Extract split file IDs from parts array
            List<String> splitFileIds = new List<String>();
            if (payloadMap.containsKey('parts')) {
                List<Object> parts = (List<Object>) payloadMap.get('parts');
                for (Object partObj : parts) {
                    Map<String, Object> partMap = (Map<String, Object>) partObj;
                    if (partMap.containsKey('contentDocumentId')) {
                        String contentDocId = String.valueOf(partMap.get('contentDocumentId'));
                        if (!splitFileIds.contains(contentDocId)) {
                            splitFileIds.add(contentDocId);
                        }
                    }
                }
            }

            if (splitFileIds.isEmpty()) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                return errorResponse('No split file IDs in callback payload', 'ValidationError', documentId);
            }

            System.debug('Extracted ' + splitFileIds.size() + ' split file IDs');

            // --- IDEMPOTENCY CHECK ---
            // analyzeMedicalRecords stores Content_Document_Id__c = splitFileIds[0], so check against those
            List<Medical_Record__c> existingRecords = [
                SELECT Id, Content_Document_Id__c, Claims__c, CreatedDate
                FROM Medical_Record__c
                WHERE Content_Document_Id__c IN :splitFileIds
                AND Claims__c = :claimId
                LIMIT 1
            ];

            if (!existingRecords.isEmpty()) {
                System.debug(LoggingLevel.INFO, 'IDEMPOTENCY: Analysis already exists for document ' + documentId + ' on claim ' + claimId + '. Skipping.');

                IntegrationLogManager.createIntegrationLog(
                    'API_SplitDocUploadCallback',
                    documentId + '_' + claimId,
                    claimId,
                    body,
                    'Skipped - already processed',
                    'Idempotent Skip',
                    null
                );

                res.statusCode = 200;
                res.addHeader('Content-Type', 'application/json');
                CallbackResponse response = new CallbackResponse();
                response.success = true;
                response.message = 'Already processed. Idempotent skip.';
                response.correlationId = documentId;
                response.recordId = existingRecords[0].Id;
                return response;
            }

            // --- CALL ANALYZE ---
            System.debug(LoggingLevel.INFO, 'Processing ' + splitFileIds.size() + ' split files for claim: ' + claimId);

            MedicalRecordController.AnalysisResponse analysisResult =
                MedicalRecordController.analyzeMedicalRecords(splitFileIds, (Id) claimId, false);

            Integer recordsCreated = (analysisResult.documents != null) ? analysisResult.documents.size() : 0;

            // --- BELL NOTIFICATION ---
            sendBellNotification(documentId, claimId, recordsCreated, true);

            // Log successful processing
            IntegrationLogManager.createIntegrationLog(
                'API_SplitDocUploadCallback',
                documentId + '_' + claimId,
                claimId,
                body,
                JSON.serialize(new Map<String, Object>{
                    'documentsCreated' => recordsCreated,
                    'splitFilesProcessed' => splitFileIds.size()
                }),
                'Completed',
                null
            );

            // Success response
            res.statusCode = 200;
            res.addHeader('Content-Type', 'application/json');

            CallbackResponse response = new CallbackResponse();
            response.success = true;
            response.correlationId = documentId;
            response.message = 'Callback processed successfully. ' + recordsCreated + ' medical records created.';
            if (analysisResult.documents != null && !analysisResult.documents.isEmpty()) {
                response.recordId = analysisResult.documents[0].Id;
            }
            return response;

        } catch (Exception e) {
            // Error handling
            System.debug(LoggingLevel.ERROR, 'Callback error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());

            // log to DT_Exception_Log__c
            DT_Logger.log(
                null,
                'Medical_Record__c',
                'Split Callback Processing',
                'API_SplitDocUploadCallback.loadPayload',
                DT_Constants.EXCEPTIONMESSAGE + e.getMessage() +
                    DT_Constants.TYPENAME + e.getTypeName() +
                    DT_Constants.STACKTRACESTRING + e.getStackTraceString(),
                true
            );

            // also log to Integration_Log__c
            IntegrationLogManager.createIntegrationLog(
                'API_SplitDocUploadCallback',
                'CALLBACK_ERROR',
                null,
                body,
                null,
                'Error',
                e.getMessage()
            );

            res.statusCode = 500;
            res.addHeader('Content-Type', 'application/json');

            return errorResponse('Error processing callback: ' + e.getMessage(), e.getTypeName(), null);
        }
    }

    /**
     * Sends a Salesforce bell notification to the user who uploaded the original document.
     * Wrapped in try/catch so notification failures never break the callback.
     */
    private static void sendBellNotification(String documentId, String claimId, Integer recordsCreated, Boolean isSuccess) {
        try {
            // figure out who uploaded the original file
            List<ContentVersion> versions = [
                SELECT CreatedById
                FROM ContentVersion
                WHERE ContentDocumentId = :documentId
                AND IsLatest = true
                LIMIT 1
            ];

            if (versions.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'Cannot send notification - ContentVersion not found for documentId: ' + documentId);
                return;
            }

            String uploaderId = versions[0].CreatedById;

            // get the custom notification type
            List<CustomNotificationType> notifTypes = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = 'Medical_Record_Processing_Complete'
                LIMIT 1
            ];

            if (notifTypes.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'CustomNotificationType "Medical_Record_Processing_Complete" not found. Skipping bell notification.');
                return;
            }

            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(notifTypes[0].Id);
            //notification.setTargetId(claimId);

            Map<String, Object> pageRef = new Map<String, Object>{
                'type' => 'standard__recordPage',
                'attributes' => new Map<String, Object>{
                    'recordId' => claimId,
                    'objectApiName' => 'Claim',
                    'actionName' => 'view'
                },
                'state' => new Map<String, Object>{
                    'c__activeTab' => 'Medical_Records_Analysis'  // Tab API name
                }
            };
            notification.setTargetPageRef(JSON.serialize(pageRef));

            if (isSuccess) {
                notification.setTitle('Medical Record Analysis Complete');
                notification.setBody('Your document has been processed. ' + recordsCreated + ' medical record(s) were created.');
            } else {
                notification.setTitle('Medical Record Processing Failed');
                notification.setBody('Your document could not be processed. Please try uploading again.');
            }

            notification.send(new Set<String>{ uploaderId });
            System.debug(LoggingLevel.INFO, 'Bell notification sent to user: ' + uploaderId);

        } catch (Exception e) {
            // notification failure should never break the callback
            System.debug(LoggingLevel.ERROR, 'Failed to send bell notification: ' + e.getMessage());
        }
    }

    /**
     * Helper to build error CallbackResponse
     */
    private static CallbackResponse errorResponse(String message, String errorType, String correlationId) {
        CallbackResponse response = new CallbackResponse();
        response.success = false;
        response.message = message;
        response.errorType = errorType;
        response.correlationId = correlationId;
        return response;
    }


    global class CallbackResponse {
        public Boolean success;
        public String message;
        public String recordId;
        public String correlationId;
        public String errorType;
    }
}