public with sharing class IDPMedicalRecordController {
    
    // Constants
    private static final String PROMPT_TEMPLATE_NAME = 'Multiple_Medical_Record_Summarizer';
    private static final Integer MAX_FILE_SIZE = 10485760; // 10 MB in bytes
    private static final Set<String> ALLOWED_FILE_TYPES = new Set<String>{'PDF'};

    // Large file splitting constants
    private static final Integer LARGE_FILE_SIZE_THRESHOLD = 15728640; // 15 MB in bytes
    private static final Integer MAX_ALLOWED_FILE_SIZE = 78643200; // 75 MB in bytes - absolute maximum

    // Content Library name for storing uploaded medical record files
    private static final String CONTENT_LIBRARY_NAME = 'Medical Record Analyzer Files';
    // Public group for Content Library access control
    private static final String ANALYZER_GROUP_NAME = 'Med Analyzer Author';

    /**
     * Analyzes a medical record PDF using Prompt Builder multimodal feature
     * Extracts 11 structured fields per document and creates Medical_Record__c records
     *
     * REDESIGNED FOR DOCUMENT-LEVEL PROCESSING:
     * - One PDF may contain multiple medical documents
     * - Creates one Medical_Record__c record per document detected
     * - All records share the same Upload_Batch_ID__c and Content_Document_Id__c
     *
     * Fields extracted: Patient Name, DOB, Provider, Date of Service, Chief Complaint,
     * Past Medical History, Treatment Plan, Diagnosis, Next Office Visit, Work Status, Summary
     *
     * @param contentDocumentId - ID of uploaded PDF file (ContentDocument)
     * @param claimId - Optional standard Claim lookup (can be null)
     * @param anonymize - If true, anonymizes PII (patient/provider names, DOB) for demo purposes
     * @return AnalysisResponse - Wrapper containing created records and metadata (including totalPages)
     * @throws AuraHandledException for validation or processing errors
     */
    @AuraEnabled
    public static AnalysisResponse analyzeMedicalRecord(Id contentDocumentId, Id claimId, Boolean anonymize) {
        System.debug(LoggingLevel.INFO, '=== START: analyzeMedicalRecord ===');
        System.debug(LoggingLevel.INFO, 'ContentDocumentId: ' + contentDocumentId);
        System.debug(LoggingLevel.INFO, 'ClaimId: ' + claimId);

        try {
            // Step 1: Validate file
            System.debug(LoggingLevel.INFO, 'Step 1: Validating file');
            validateFile(contentDocumentId);

            // Step 3: Get PDF filename for reference
            System.debug(LoggingLevel.INFO, 'Step 3: Getting PDF filename');
            String pdfName = getPdfFileName(contentDocumentId);
            System.debug(LoggingLevel.INFO, 'PDF Filename: ' + pdfName);

            // Step 4: Call Prompt Builder with file input
            System.debug(LoggingLevel.INFO, 'Step 4: Calling Prompt Builder AI analysis');
            String jsonResponse = callPromptBuilderWithFile(contentDocumentId);
            System.debug(LoggingLevel.INFO, 'AI Response Length: ' + (jsonResponse != null ? jsonResponse.length() : 0) + ' chars');

            // Step 5: Parse JSON response
            System.debug(LoggingLevel.INFO, 'Step 5: Parsing JSON response');
            System.debug('jsonResponse11111'+jsonResponse);
            Map<String, Object> parsed = parseJsonResponse(jsonResponse);
            System.debug(LoggingLevel.INFO, 'Parsed keys: ' + (parsed != null ? String.join(new List<String>(parsed.keySet()), ', ') : 'null'));

            // Step 6: Validate AI response structure and sanity checks
            System.debug(LoggingLevel.INFO, 'Step 6: Validating AI response');
            validateAIResponse(parsed);

            // Step 7: Generate unique batch ID for this upload
            System.debug(LoggingLevel.INFO, 'Step 7: Generating upload batch ID');
            String uploadBatchId = generateUploadBatchId();
            System.debug(LoggingLevel.INFO, 'Upload Batch ID: ' + uploadBatchId);

            // Step 8: Create Medical_Record__c records (one per document)
            System.debug(LoggingLevel.INFO, 'Step 8: Creating Medical_Record__c objects');
            List<Medical_Record__c> records;
            if (parsed.containsKey('documents')) {
                // New format: Multiple documents with full field extraction
                List<Object> documents = (List<Object>) parsed.get('documents');
                // Extract riskAnalysis from root level (applies to all documents)
                Map<String, Object> riskAnalysis = parsed.containsKey('riskAnalysis')
                    ? (Map<String, Object>) parsed.get('riskAnalysis')
                    : null;
                records = createMedicalRecordsFromDocuments(
                    documents,
                    contentDocumentId,
                    claimId,
                    uploadBatchId,
                    pdfName,
                    jsonResponse,
                    riskAnalysis
                );
            } else {
                // Legacy format or single document: Create one record
                Medical_Record__c record = createMedicalRecordLegacy(
                    parsed,
                    contentDocumentId,
                    claimId,
                    uploadBatchId,
                    pdfName,
                    jsonResponse
                );
                records = new List<Medical_Record__c>{ record };
            }

            System.debug(LoggingLevel.INFO, 'Created ' + records.size() + ' Medical_Record__c objects');

            // Step 8.5: Apply anonymization if requested (for demo purposes)
            /*if (anonymize == true && claimId != null) {
                System.debug(LoggingLevel.INFO, 'Step 8.5: Applying anonymization for demo mode');
                MedicalRecordAnonymizer anonymizer = new MedicalRecordAnonymizer(claimId);
                records = anonymizer.anonymize(records);
                System.debug(LoggingLevel.INFO, 'Anonymization complete');
            }*/

            // Step 9: Insert with FLS/CRUD check
            System.debug(LoggingLevel.INFO, 'Step 9: Inserting records into database');
            if (!Schema.sObjectType.Medical_Record__c.isCreateable()) {
                throw new AuraHandledException('Insufficient permissions to create Medical Records');
            }

            insert records;
            System.debug(LoggingLevel.INFO, 'Successfully inserted ' + records.size() + ' records');

            // Log the IDs of created records
            List<Id> recordIds = new List<Id>();
            for (Medical_Record__c rec : records) {
                recordIds.add(rec.Id);
                System.debug(LoggingLevel.INFO, 'Created Medical_Record__c: ' + rec.Id);
            }

            // Step 10: Auto-update parent claim if linked
            if (claimId != null) {
                System.debug(LoggingLevel.INFO, 'Step 10: Updating parent Claim__c');
                ClaimAutoUpdateService.updateClaimFromMedicalRecords(claimId, anonymize);

                // Step 10.5: Publish Platform Event for LWC auto-refresh
                System.debug(LoggingLevel.INFO, 'Step 10.5: Publishing Medical_Record_Changed__e event');
                publishMedicalRecordChangedEvent(claimId, recordIds);
            }

            // Step 11: Query and return full records
            System.debug(LoggingLevel.INFO, 'Step 11: Querying full record details');
            List<Medical_Record__c> fullRecords = getMedicalRecordsByIds(recordIds);

            // Step 12: Extract metadata from AI response
            System.debug(LoggingLevel.INFO, 'Step 12: Extracting metadata from AI response');
            Integer totalPages = extractTotalPages(parsed);
            Integer totalDocuments = fullRecords.size();

            // Create response wrapper with records and metadata
            AnalysisMetadata metadata = new AnalysisMetadata(totalPages, totalDocuments);
            AnalysisResponse response = new AnalysisResponse(fullRecords, metadata);

            System.debug(LoggingLevel.INFO, 'Total Pages from AI: ' + totalPages);
            System.debug(LoggingLevel.INFO, 'Total Documents: ' + totalDocuments);
            System.debug(LoggingLevel.INFO, '=== END: analyzeMedicalRecord - SUCCESS ===');
            return response;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '=== EXCEPTION in analyzeMedicalRecord ===');
            System.debug(LoggingLevel.ERROR, 'Exception Type: ' + e.getTypeName());
            System.debug(LoggingLevel.ERROR, 'Error Message: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR, '=== END: analyzeMedicalRecord - FAILED ===');
            throw new AuraHandledException('Failed to analyze medical record: ' + e.getMessage());
        }
    }

    /**
     * Analyzes multiple medical record PDFs using Prompt Builder multimodal feature
     * Used when a large PDF is split into multiple smaller files
     * All files are passed to Prompt Builder at once as Input:PDF_File_1, Input:PDF_File_2, etc.
     *
     * @param contentDocumentIds - List of ContentDocument IDs (split files)
     * @param claimId - Optional standard Claim lookup (can be null)
     * @param anonymize - If true, anonymizes PII for demo purposes
     * @return AnalysisResponse - Wrapper containing created records and metadata
     * @throws AuraHandledException for validation or processing errors
     */
    @AuraEnabled
    public static AnalysisResponse analyzeMedicalRecords(List<String> contentDocumentIds, Id claimId, Boolean anonymize) {
        System.debug(LoggingLevel.INFO, '=== START: analyzeMedicalRecords (Multiple Files) ===');
        System.debug(LoggingLevel.INFO, 'Number of ContentDocumentIds: ' + (contentDocumentIds != null ? contentDocumentIds.size() : 0));
        System.debug(LoggingLevel.INFO, 'ClaimId: ' + claimId);

        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            throw new AuraHandledException('At least one ContentDocumentId is required');
        }

        try {
            // Step 1: Validate all files
            System.debug(LoggingLevel.INFO, 'Step 1: Validating ' + contentDocumentIds.size() + ' files');
            for (String docId : contentDocumentIds) {
                validateFile(docId);
            }

            // Step 2: Get first PDF filename for reference
            System.debug(LoggingLevel.INFO, 'Step 2: Getting PDF filename');
            String pdfName = getPdfFileName(contentDocumentIds[0]);
            System.debug(LoggingLevel.INFO, 'Primary PDF Filename: ' + pdfName);

            // Step 3: Call Prompt Builder with all files at once
            System.debug(LoggingLevel.INFO, 'Step 3: Calling Prompt Builder AI analysis with ' + contentDocumentIds.size() + ' files');
            String jsonResponse = callPromptBuilderWithFiles(contentDocumentIds);
            System.debug(LoggingLevel.INFO, 'AI Response Length: ' + (jsonResponse != null ? jsonResponse.length() : 0) + ' chars');

            // Step 4: Parse JSON response
            System.debug(LoggingLevel.INFO, 'Step 4: Parsing JSON response');
            Map<String, Object> parsed = parseJsonResponse(jsonResponse);
            System.debug(LoggingLevel.INFO, 'Parsed keys: ' + (parsed != null ? String.join(new List<String>(parsed.keySet()), ', ') : 'null'));

            // Step 5: Validate AI response structure
            System.debug(LoggingLevel.INFO, 'Step 5: Validating AI response');
            validateAIResponse(parsed);

            // Step 6: Generate unique batch ID for this upload
            System.debug(LoggingLevel.INFO, 'Step 6: Generating upload batch ID');
            String uploadBatchId = generateUploadBatchId();
            System.debug(LoggingLevel.INFO, 'Upload Batch ID: ' + uploadBatchId);

            // Step 7: Create Medical_Record__c records (one per document)
            System.debug(LoggingLevel.INFO, 'Step 7: Creating Medical_Record__c objects');
            List<Medical_Record__c> records;

            // Use first contentDocumentId as the primary reference
            Id primaryContentDocumentId = contentDocumentIds[0];

            if (parsed.containsKey('documents')) {
                List<Object> documents = (List<Object>) parsed.get('documents');
                Map<String, Object> riskAnalysis = parsed.containsKey('riskAnalysis')
                    ? (Map<String, Object>) parsed.get('riskAnalysis')
                    : null;
                records = createMedicalRecordsFromDocuments(
                    documents,
                    primaryContentDocumentId,
                    claimId,
                    uploadBatchId,
                    pdfName,
                    jsonResponse,
                    riskAnalysis
                );
            } else {
                Medical_Record__c record = createMedicalRecordLegacy(
                    parsed,
                    primaryContentDocumentId,
                    claimId,
                    uploadBatchId,
                    pdfName,
                    jsonResponse
                );
                records = new List<Medical_Record__c>{ record };
            }

            System.debug(LoggingLevel.INFO, 'Created ' + records.size() + ' Medical_Record__c objects');

            // Step 8: Apply anonymization if requested
            /*if (anonymize == true && claimId != null) {
                System.debug(LoggingLevel.INFO, 'Step 8: Applying anonymization for demo mode');
                MedicalRecordAnonymizer anonymizer = new MedicalRecordAnonymizer(claimId);
                records = anonymizer.anonymize(records);
                System.debug(LoggingLevel.INFO, 'Anonymization complete');
            }*/

            // Step 9: Insert with FLS/CRUD check
            System.debug(LoggingLevel.INFO, 'Step 9: Inserting records into database');
            if (!Schema.sObjectType.Medical_Record__c.isCreateable()) {
                throw new AuraHandledException('Insufficient permissions to create Medical Records');
            }

            insert records;
            System.debug(LoggingLevel.INFO, 'Successfully inserted ' + records.size() + ' records');

            // Log the IDs of created records
            List<Id> recordIds = new List<Id>();
            for (Medical_Record__c rec : records) {
                recordIds.add(rec.Id);
                System.debug(LoggingLevel.INFO, 'Created Medical_Record__c: ' + rec.Id);
            }

            // Step 10: Auto-update parent claim if linked
            if (claimId != null) {
                System.debug(LoggingLevel.INFO, 'Step 10: Updating parent Claim__c');
                ClaimAutoUpdateService.updateClaimFromMedicalRecords(claimId, anonymize);
                publishMedicalRecordChangedEvent(claimId, recordIds);
            }

            // Step 11: Query and return full records
            System.debug(LoggingLevel.INFO, 'Step 11: Querying full record details');
            List<Medical_Record__c> fullRecords = getMedicalRecordsByIds(recordIds);

            // Step 12: Extract metadata from AI response
            System.debug(LoggingLevel.INFO, 'Step 12: Extracting metadata from AI response');
            Integer totalPages = extractTotalPages(parsed);
            Integer totalDocuments = fullRecords.size();

            AnalysisMetadata metadata = new AnalysisMetadata(totalPages, totalDocuments);
            AnalysisResponse response = new AnalysisResponse(fullRecords, metadata);

            System.debug(LoggingLevel.INFO, 'Total Pages from AI: ' + totalPages);
            System.debug(LoggingLevel.INFO, 'Total Documents: ' + totalDocuments);
            System.debug(LoggingLevel.INFO, '=== END: analyzeMedicalRecords - SUCCESS ===');
            return response;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '=== EXCEPTION in analyzeMedicalRecords ===');
            System.debug(LoggingLevel.ERROR, 'Exception Type: ' + e.getTypeName());
            System.debug(LoggingLevel.ERROR, 'Error Message: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR, '=== END: analyzeMedicalRecords - FAILED ===');
            throw new AuraHandledException('Failed to analyze medical records: ' + e.getMessage());
        }
    }

    /**
     * Retrieves medical records associated with a claim
     *
     * @param claimId - Standard Claim record ID
     * @return List<Medical_Record__c> - Medical records for the claim
     */
    @AuraEnabled(cacheable=true)
    public static List<Medical_Record__c> getMedicalRecordsByClaim(Id claimId) {
        if (!Schema.sObjectType.Medical_Record__c.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access Medical Records');
        }

        return [
            SELECT Id, Name, Patient_Name__c, Date_of_Birth__c, Provider__c,
                   Date_of_Service__c, Chief_Complaint__c,
                   Past_Medical_History__c, Treatment_Plan__c, Diagnosis__c,
                   Next_Office_Visit__c, Work_Status__c, Content_Document_Id__c,
                   CreatedDate, Document_Type__c, Document_Count__c,
                   Requires_Review__c, Risk_Score__c, Summary__c
            FROM Medical_Record__c
            WHERE Claims__c = :claimId
            ORDER BY Date_of_Service__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 100
        ];
    }

    /**
     * Retrieves a single medical record by ID
     *
     * @param recordId - Medical_Record__c ID
     * @return Medical_Record__c - Full record details
     */
    @AuraEnabled(cacheable=true)
    public static Medical_Record__c getMedicalRecordById(Id recordId) {
        if (!Schema.sObjectType.Medical_Record__c.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access Medical Records');
        }

        List<Medical_Record__c> records = [
            SELECT Id, Name, Patient_Name__c, Date_of_Birth__c, Provider__c,
                   Date_of_Service__c, Chief_Complaint__c,
                   Past_Medical_History__c, Treatment_Plan__c, Diagnosis__c,
                   Next_Office_Visit__c, Work_Status__c, Content_Document_Id__c,
                   Claims__c, Raw_JSON__c, CreatedDate,
                   Document_Type__c, Document_Count__c, Document_Listing__c,
                   High_Risk_Indicators__c, Requires_Review__c, Analysis_Summary__c,
                   Risk_Score__c, Upload_Batch_ID__c, Document_Sequence_Number__c,
                   Source_PDF_Name__c, Summary__c
            FROM Medical_Record__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (records.isEmpty()) {
            throw new AuraHandledException('Medical record not found');
        }

        return records[0];
    }

    /**
     * Retrieves multiple medical records by IDs
     * Used after bulk insert to return full records
     *
     * @param recordIds - List of Medical_Record__c IDs
     * @return List<Medical_Record__c> - Full record details
     */
    private static List<Medical_Record__c> getMedicalRecordsByIds(List<Id> recordIds) {
        if (!Schema.sObjectType.Medical_Record__c.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access Medical Records');
        }

        return [
            SELECT Id, Name, Patient_Name__c, Date_of_Birth__c, Provider__c,
                   Date_of_Service__c, Chief_Complaint__c,
                   Past_Medical_History__c, Treatment_Plan__c, Diagnosis__c,
                   Next_Office_Visit__c, Work_Status__c, Content_Document_Id__c,
                   Claims__c, Raw_JSON__c, CreatedDate,
                   Document_Type__c, Document_Count__c, Document_Listing__c,
                   High_Risk_Indicators__c, Requires_Review__c, Analysis_Summary__c,
                   Risk_Score__c, Upload_Batch_ID__c, Document_Sequence_Number__c,
                   Source_PDF_Name__c, Summary__c
            FROM Medical_Record__c
            WHERE Id IN :recordIds
            ORDER BY Document_Sequence_Number__c ASC NULLS LAST, CreatedDate DESC
            LIMIT 100
        ];
    }

    /**
     * Re-analyzes an existing medical record using its stored ContentDocument ID
     * UPDATED FOR BATCH RE-ANALYSIS:
     * - Deletes all records from the same upload batch
     * - Re-analyzes the PDF and creates fresh records
     * - Maintains Upload_Batch_ID__c for grouping
     *
     * @param medicalRecordId - Medical_Record__c ID from the batch
     * @param anonymize - If true, anonymizes PII (patient/provider names, DOB) for demo purposes
     * @return List<Medical_Record__c> - New records created from re-analysis
     */
    @AuraEnabled
    public static List<Medical_Record__c> reanalyzeMedicalRecord(Id medicalRecordId, Boolean anonymize) {
        try {
            // Get existing record with ContentDocument ID and Batch ID
            Medical_Record__c existing = getMedicalRecordById(medicalRecordId);

            if (String.isBlank(existing.Content_Document_Id__c)) {
                throw new AuraHandledException('No PDF file associated with this medical record');
            }

            // Query all records from the same upload batch
            List<Medical_Record__c> batchRecords = [
                SELECT Id
                FROM Medical_Record__c
                WHERE Upload_Batch_ID__c = :existing.Upload_Batch_ID__c
                OR (Content_Document_Id__c = :existing.Content_Document_Id__c
                    AND Claims__c = :existing.Claims__c
                    AND Upload_Batch_ID__c = null)
                LIMIT 100
            ];

            // Delete old records from this batch
            if (!Schema.sObjectType.Medical_Record__c.isDeletable()) {
                throw new AuraHandledException('Insufficient permissions to delete Medical Records');
            }
            delete batchRecords;

            // Validate file still exists
            validateFile(existing.Content_Document_Id__c);

            // Get PDF filename
            String pdfName = getPdfFileName(existing.Content_Document_Id__c);

            // Call Prompt Builder with stored file
            String jsonResponse = callPromptBuilderWithFile(existing.Content_Document_Id__c);

            // Parse JSON response
            Map<String, Object> parsed = parseJsonResponse(jsonResponse);

            // Reuse the same batch ID (maintains grouping)
            String uploadBatchId = existing.Upload_Batch_ID__c != null
                ? existing.Upload_Batch_ID__c
                : generateUploadBatchId();

            // Create new Medical_Record__c records (one per document)
            List<Medical_Record__c> newRecords;
            if (parsed.containsKey('documents')) {
                List<Object> documents = (List<Object>) parsed.get('documents');
                // Extract riskAnalysis from root level (applies to all documents)
                Map<String, Object> riskAnalysis = parsed.containsKey('riskAnalysis')
                    ? (Map<String, Object>) parsed.get('riskAnalysis')
                    : null;
                newRecords = createMedicalRecordsFromDocuments(
                    documents,
                    existing.Content_Document_Id__c,
                    existing.Claims__c,
                    uploadBatchId,
                    pdfName,
                    jsonResponse,
                    riskAnalysis
                );
            } else {
                Medical_Record__c record = createMedicalRecordLegacy(
                    parsed,
                    existing.Content_Document_Id__c,
                    existing.Claims__c,
                    uploadBatchId,
                    pdfName,
                    jsonResponse
                );
                newRecords = new List<Medical_Record__c>{ record };
            }

            // Apply anonymization if requested (for demo purposes)
            /*if (anonymize == true && existing.Claims__c != null) {
                MedicalRecordAnonymizer anonymizer = new MedicalRecordAnonymizer(existing.Claims__c);
                newRecords = anonymizer.anonymize(newRecords);
            }*/

            // Insert new records
            if (!Schema.sObjectType.Medical_Record__c.isCreateable()) {
                throw new AuraHandledException('Insufficient permissions to create Medical Records');
            }
            insert newRecords;

            // Return refreshed records
            List<Id> recordIds = new List<Id>();
            for (Medical_Record__c rec : newRecords) {
                recordIds.add(rec.Id);
            }

            // Auto-update parent claim if linked
            if (existing.Claims__c != null) {
                ClaimAutoUpdateService.updateClaimFromMedicalRecords(existing.Claims__c, anonymize);

                // Publish Platform Event for LWC auto-refresh
                publishMedicalRecordChangedEvent(existing.Claims__c, recordIds);
            }

            return getMedicalRecordsByIds(recordIds);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error re-analyzing medical record: ' + e.getMessage());
            throw new AuraHandledException('Failed to re-analyze medical record: ' + e.getMessage());
        }
    }

    /**
     * Gets all PDF files attached to a Claim record
     * Used for re-analyzing existing documents
     *
     * @param claimId - Claim__c record ID
     * @return List of file information (ContentDocumentId, Title, ContentSize, CreatedDate, FileType)
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getClaimFiles(Id claimId) {
        try {
            if (claimId == null) {
                return new List<Map<String, Object>>();
            }

            // Query ContentDocumentLinks to find files attached to this Claim
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId, ContentDocument.Title,
                       ContentDocument.LatestPublishedVersion.ContentSize,
                       ContentDocument.LatestPublishedVersion.FileType,
                       ContentDocument.CreatedDate
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :claimId
                AND ContentDocument.LatestPublishedVersion.FileType = 'PDF'
                ORDER BY ContentDocument.CreatedDate DESC
                LIMIT 100
            ];

            // Transform to simple map format for LWC
            List<Map<String, Object>> files = new List<Map<String, Object>>();
            for (ContentDocumentLink link : links) {
                Map<String, Object> fileInfo = new Map<String, Object>();
                fileInfo.put('contentDocumentId', link.ContentDocumentId);
                fileInfo.put('title', link.ContentDocument.Title);
                fileInfo.put('contentSize', link.ContentDocument.LatestPublishedVersion.ContentSize);
                fileInfo.put('fileType', link.ContentDocument.LatestPublishedVersion.FileType);
                fileInfo.put('createdDate', link.ContentDocument.CreatedDate);
                files.add(fileInfo);
            }

            return files;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting claim files: ' + e.getMessage());
            throw new AuraHandledException('Failed to retrieve claim files: ' + e.getMessage());
        }
    }

    /**
     * Updates the "Med Analyzer Author" public group membership.
     * Removes all existing members and adds the current running user.
     * Called at the start of the upload flow to ensure the uploading user has library access.
     */
    @AuraEnabled
    public static void updateAnalyzerGroupMembership() {
        new ElevatedAccess().updateGroupMembership(ANALYZER_GROUP_NAME, UserInfo.getUserId());
    }

    /**
     * Adds an uploaded file to the "Medical Record Analyzer Files" Content Library
     * and organizes it into a Claim Number folder.
     * Delegates to ElevatedAccess inner class to bypass sharing rules on ContentWorkspace.
     *
     * @param contentDocumentId The ContentDocument ID of the uploaded file
     * @param claimId The Claim record ID
     */
    @AuraEnabled
    public static void moveFileToLibrary(Id contentDocumentId, Id claimId) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('ContentDocument ID is required');
        }
        try {
            new ElevatedAccess().addFileToLibraryAndOrganize(CONTENT_LIBRARY_NAME, contentDocumentId, claimId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error adding file to library: ' + e.getMessage());
            throw new AuraHandledException('Failed to add file to library: ' + e.getMessage());
        }
    }

    // ========== PRIVATE HELPER METHODS ==========

    /**
     * Checks if medical records already exist for this file content (using checksum)
     * Prevents duplicate analysis of the same PDF file
     *
     * REDESIGNED: Uses ContentVersion.Checksum instead of ContentDocument ID
     * This properly detects when the SAME FILE is uploaded multiple times,
     * even though each upload creates a new ContentDocument with different ID.
     *
     * @param contentDocumentId - ContentDocument ID to get checksum from
     * @return List<Medical_Record__c> - Existing records for this file content (empty if none found)
     */
    private static List<Medical_Record__c> checkForDuplicates(Id contentDocumentId) {
        if (!Schema.sObjectType.Medical_Record__c.isAccessible()) {
            return new List<Medical_Record__c>();
        }

        // Get the MD5 checksum of the uploaded file
        String fileChecksum = getFileChecksum(contentDocumentId);

        if (String.isBlank(fileChecksum)) {
            System.debug('Unable to retrieve file checksum - proceeding without duplicate check');
            return new List<Medical_Record__c>();
        }

        // Query for existing records with matching checksum
        List<Medical_Record__c> existingRecords = [
            SELECT Id, Name, Patient_Name__c, Date_of_Birth__c, Provider__c,
                   Date_of_Service__c, Chief_Complaint__c,
                   Past_Medical_History__c, Treatment_Plan__c, Diagnosis__c,
                   Next_Office_Visit__c, Work_Status__c, Content_Document_Id__c,
                   Claims__c, Raw_JSON__c, CreatedDate,
                   Document_Type__c, Document_Count__c, Document_Listing__c,
                   High_Risk_Indicators__c, Requires_Review__c, Analysis_Summary__c,
                   Risk_Score__c, Upload_Batch_ID__c, Document_Sequence_Number__c,
                   Source_PDF_Name__c, Summary__c, File_Checksum__c,
                   Analysis_Hash__c, Analysis_Confidence__c, Has_Inconsistent_Analysis__c
            FROM Medical_Record__c
            WHERE File_Checksum__c = :fileChecksum
            ORDER BY Document_Sequence_Number__c ASC NULLS LAST, CreatedDate DESC
            LIMIT 100
        ];

        // Verify the associated ContentDocument still exists
        // If the file was deleted, we should re-analyze
        if (!existingRecords.isEmpty()) {
            Set<Id> contentDocIds = new Set<Id>();
            for (Medical_Record__c rec : existingRecords) {
                if (rec.Content_Document_Id__c != null) {
                    contentDocIds.add(rec.Content_Document_Id__c);
                }
            }

            // Check if any of the ContentDocuments still exist
            List<ContentDocument> existingDocs = [
                SELECT Id FROM ContentDocument WHERE Id IN :contentDocIds
            ];

            // If no ContentDocuments exist anymore, the files were deleted - allow re-analysis
            if (existingDocs.isEmpty()) {
                System.debug('Found existing records but all associated files have been deleted - allowing re-analysis');
                return new List<Medical_Record__c>();
            }
        }

        return existingRecords;
    }

    /**
     * Retrieves the MD5 checksum of a file from ContentVersion
     * Salesforce automatically generates MD5 hash for all uploaded files
     *
     * @param contentDocumentId - ContentDocument ID
     * @return String - MD5 checksum (or null if unable to retrieve)
     */
    private static String getFileChecksum(Id contentDocumentId) {
        try {
            List<ContentVersion> versions = [
                SELECT Checksum
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];

            if (versions.isEmpty()) {
                return null;
            }

            return versions[0].Checksum;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving file checksum: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Validates the uploaded file meets requirements
     * - Must be PDF format
     * - Must be under 10 MB
     * - Must exist and be accessible
     */
    private static void validateFile(Id contentDocumentId) {
        // Query ContentVersion for file metadata
        List<ContentVersion> versions = [
            SELECT FileType, ContentSize, Title
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            throw new AuraHandledException('File not found or not accessible');
        }

        ContentVersion cv = versions[0];

        // Validate file type
        if (!ALLOWED_FILE_TYPES.contains(cv.FileType?.toUpperCase())) {
            throw new AuraHandledException('Invalid file type. Only PDF files are supported. Uploaded: ' + cv.FileType);
        }

        // Validate file size
        if (cv.ContentSize > LARGE_FILE_SIZE_THRESHOLD) {
            Decimal sizeMB = cv.ContentSize / 15728640.0;
            throw new AuraHandledException('File size (' + sizeMB.setScale(2) + ' MB) exceeds maximum limit of 15 MB');
        }
    }

    /**
     * Retrieves the filename of the uploaded PDF
     * Used for storing Source_PDF_Name__c field
     */
    private static String getPdfFileName(Id contentDocumentId) {
        List<ContentVersion> versions = [
            SELECT Title, PathOnClient
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            return 'Unknown.pdf';
        }

        // Use PathOnClient if available (includes extension), otherwise Title
        String filename = versions[0].PathOnClient != null
            ? versions[0].PathOnClient
            : versions[0].Title;

        return filename;
    }

    /**
     * Generates a unique Upload Batch ID using UUID
     * All Medical_Record__c records from the same PDF upload share this ID
     */
    private static String generateUploadBatchId() {
        // Generate UUID (example: 550e8400-e29b-41d4-a716-446655440000)
        Blob b = Crypto.generateAesKey(128);
        String hex = EncodingUtil.convertToHex(b);

        // Format as UUID: 8-4-4-4-12
        String uuid = hex.substring(0, 8) + '-'
            + hex.substring(8, 12) + '-'
            + hex.substring(12, 16) + '-'
            + hex.substring(16, 20) + '-'
            + hex.substring(20, 32);

        return uuid;
    }

    /**
     * Generates SHA-256 hash of AI extraction results
     * Used to detect when re-analyzing the same file produces different results
     *
     * Creates canonical representation from key fields:
     * - dateOfService
     * - provider
     * - documentType
     * - diagnosis
     *
     * Documents are sorted before hashing to ensure order-independence
     *
     * @param documents - List of document objects from AI extraction
     * @return String - 64-character hex SHA-256 hash
     */
    private static String generateAnalysisHash(List<Object> documents) {
        if (documents == null || documents.isEmpty()) {
            return null;
        }

        List<String> docStrings = new List<String>();

        for (Object docObj : documents) {
            Map<String, Object> doc = (Map<String, Object>) docObj;

            // Create deterministic string representation using key fields
            String docString = String.valueOf(doc.get('dateOfService')) + '|' +
                              String.valueOf(doc.get('provider')) + '|' +
                              String.valueOf(doc.get('documentType')) + '|' +
                              String.valueOf(doc.get('diagnosis'));

            docStrings.add(docString);
        }

        // Sort to ensure order doesn't affect hash
        docStrings.sort();

        // Generate SHA-256 hash
        String canonical = String.join(docStrings, '\n');
        Blob canonicalBlob = Blob.valueOf(canonical);
        Blob hashBlob = Crypto.generateDigest('SHA-256', canonicalBlob);

        return EncodingUtil.convertToHex(hashBlob);
    }

    /**
     * Validates AI response structure and performs sanity checks
     * Throws AuraHandledException if response is invalid or suspicious
     *
     * Checks:
     * - Response contains 'documents' array
     * - Document count is reasonable (1-100)
     * - If metadata exists, validates confidence score and count consistency
     *
     * @param parsed - Parsed JSON response from AI
     * @throws AuraHandledException for validation failures
     */
    private static void validateAIResponse(Map<String, Object> parsed) {
        // Check required fields
        if (!parsed.containsKey('documents')) {
            throw new AuraHandledException('AI response missing "documents" array. Please verify the Prompt Template returns the correct format.');
        }

        List<Object> documents = (List<Object>) parsed.get('documents');

        // Sanity check: Must have at least 1 document
        if (documents == null || documents.isEmpty()) {
            throw new AuraHandledException('AI found 0 documents in the PDF. Please verify the file contains readable medical records and try again.');
        }

        // Sanity check: Suspiciously high document count (possible hallucination)
        if (documents.size() > 100) {
            throw new AuraHandledException('AI detected ' + documents.size() + ' documents, which is unusually high. This may indicate an analysis error. Please verify the PDF and try again, or contact support.');
        }

        // If metadata exists, perform additional validation
        if (parsed.containsKey('metadata')) {
            Map<String, Object> metadata = (Map<String, Object>) parsed.get('metadata');

            // Check document count consistency
            if (metadata.containsKey('totalDocuments')) {
                Integer declaredCount = (Integer) metadata.get('totalDocuments');
                Integer actualCount = documents.size();

                if (declaredCount != actualCount) {
                    System.debug(LoggingLevel.WARN, 'AI count mismatch! Declared: ' + declaredCount + ', Actual: ' + actualCount);
                    // Don't throw - just log warning. The actual documents array is source of truth.
                }
            }

            // Check confidence score
            if (metadata.containsKey('confidence')) {
                try {
                    Decimal confidence = Decimal.valueOf(String.valueOf(metadata.get('confidence')));

                    if (confidence < 70) {
                        System.debug(LoggingLevel.WARN, 'Low AI confidence score: ' + confidence + '%');
                        // Don't throw - proceed but log warning for potential manual review
                    }
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Unable to parse confidence score: ' + e.getMessage());
                }
            }
        }
    }

    /**
     * Calls Prompt Builder with file input using multimodal feature
     * Follows ClientVisitController.cls pattern (lines 167-194)
     *
     * @param contentDocumentId - ContentDocument ID (NOT ContentVersion)
     * @return String - JSON response from LLM
     */
    private static String callPromptBuilderWithFile(Id contentDocumentId) {
        // Build Prompt Builder input (same pattern as ClientVisitController)
        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
        input.additionalConfig.numGenerations = 1;

        // CRITICAL FOR CONSISTENCY: Set temperature to 0 for deterministic results
        // This ensures the same PDF produces the same analysis every time
        input.additionalConfig.temperature = 0;

        // Create input parameters map
        Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();

        // Add file input (multimodal feature - Spring '25)
        // Pass ContentDocumentId wrapped in map with 'id' key
        ConnectApi.WrappedValue fileValue = new ConnectApi.WrappedValue();
        Map<String, String> fileIdMap = new Map<String, String>();
        fileIdMap.put('id', contentDocumentId);
        fileValue.value = fileIdMap;
        valueMap.put('Input:PDF_File_1', fileValue);

        input.inputParams = valueMap;

        // Call Prompt Builder template
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    PROMPT_TEMPLATE_NAME,
                    input
                );

            // Extract generated text from response
            if (result.generations != null && !result.generations.isEmpty()) {
                return result.generations[0].text;
            } else {
                throw new AuraHandledException('No response generated from Prompt Builder');
            }

        } catch (ConnectApi.ConnectApiException e) {
            // Handle specific Prompt Builder errors
            if (e.getMessage().contains('not found')) {
                throw new AuraHandledException('Prompt template "' + PROMPT_TEMPLATE_NAME + '" not found. Please create it in Einstein Setup → Prompt Builder');
            } else if (e.getMessage().contains('model does not support')) {
                throw new AuraHandledException('The selected model does not support file inputs. Please use GPT-4 Omni or Gemini 2.0 Flash');
            } else {
                throw new AuraHandledException('Prompt Builder error: ' + e.getMessage());
            }
        }
    }

    /**
     * Calls Prompt Builder with multiple file inputs using multimodal feature
     * Supports multiple files with parameters: Input:PDF_File_1, Input:PDF_File_2, etc.
     *
     * @param contentDocumentIds - List of ContentDocument IDs (NOT ContentVersion)
     * @return String - JSON response from LLM
     */
    private static String callPromptBuilderWithFiles(List<String> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            throw new AuraHandledException('At least one ContentDocumentId is required');
        }

        // Build Prompt Builder input
        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
        input.additionalConfig.numGenerations = 1;

        // CRITICAL FOR CONSISTENCY: Set temperature to 0 for deterministic results
        input.additionalConfig.temperature = 0;

        // Create input parameters map
        Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();

        // Add file inputs dynamically based on number of files
        // Uses Input:PDF_File_1, Input:PDF_File_2, etc.
        for (Integer i = 0; i < contentDocumentIds.size(); i++) {
            ConnectApi.WrappedValue fileValue = new ConnectApi.WrappedValue();
            Map<String, String> fileIdMap = new Map<String, String>();
            fileIdMap.put('id', contentDocumentIds[i]);
            fileValue.value = fileIdMap;

            // Parameter naming: Input:PDF_File_1, Input:PDF_File_2, etc.
            String paramName = 'Input:PDF_File_' + (i + 1);
            valueMap.put(paramName, fileValue);

            System.debug(LoggingLevel.INFO, 'Added file parameter: ' + paramName + ' = ' + contentDocumentIds[i]);
        }

        input.inputParams = valueMap;

        System.debug(LoggingLevel.INFO, 'Calling Prompt Builder with ' + contentDocumentIds.size() + ' file(s)');

        // Call Prompt Builder template
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    PROMPT_TEMPLATE_NAME,
                    input
                );

            // Extract generated text from response
            if (result.generations != null && !result.generations.isEmpty()) {
                return result.generations[0].text;
            } else {
                throw new AuraHandledException('No response generated from Prompt Builder');
            }

        } catch (ConnectApi.ConnectApiException e) {
            // Handle specific Prompt Builder errors
            System.debug('Prompt Builder error: ' + e.getMessage());
            if (e.getMessage().contains('not found')) {
                throw new AuraHandledException('Prompt template "' + PROMPT_TEMPLATE_NAME + '" not found. Please create it in Einstein Setup → Prompt Builder');
            } else if (e.getMessage().contains('model does not support')) {
                throw new AuraHandledException('The selected model does not support file inputs. Please use GPT-4 Omni or Gemini 2.0 Flash');
            } else {
                throw new AuraHandledException('Prompt Builder error: ' + e.getMessage());
            }
        }
    }

    /**
     * Parses JSON response from LLM
     *
     * Enhanced format for Workers Compensation (backwards compatible):
     * {
     *   "extractedData": {  // Optional wrapper for new format
     *     "provider": "string",
     *     "dateOfService": "YYYY-MM-DD",
     *     "chiefComplaint": "string",
     *     "pastMedicalHistory": "string",
     *     "treatmentPlan": "string",
     *     "diagnosis": "string",
     *     "nextOfficeVisit": "YYYY-MM-DD" or null,
     *     "workStatus": "Full Duty|Light Duty|Off Work|Unknown"
     *   },
     *   "documents": [  // Optional - multiple documents in PDF
     *     {"type": "ER Visit", "date": "YYYY-MM-DD", "provider": "...", "keyFindings": "..."}
     *   ],
     *   "riskAnalysis": {  // Optional - risk assessment
     *     "highRisk": true/false,
     *     "riskScore": 0-100,
     *     "indicators": ["Lengthy ER history", "Prior injury"],
     *     "recommendation": "Escalate to senior adjuster"
     *   }
     * }
     *
     * Also supports legacy flat format (direct fields at root level)
     */
    private static Map<String, Object> parseJsonResponse(String jsonResponse) {
        System.debug('jsonResponse::::'+jsonResponse);
        try {
            // Remove markdown code block markers if present
            String cleanJson = jsonResponse.trim();
            if (cleanJson.startsWith('```json')) {
                cleanJson = cleanJson.substringAfter('```json').substringBefore('```').trim();
            } else if (cleanJson.startsWith('```')) {
                cleanJson = cleanJson.substringAfter('```').substringBefore('```').trim();
            }

            System.debug('cleanJson::::'+cleanJson);
            // Parse JSON
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleanJson);

            return parsed;

        } catch (JSONException e) {
            throw new AuraHandledException('Invalid JSON response from LLM. Please verify the Prompt template returns valid JSON format. Error: ' + e.getMessage());
        }
    }

    /**
     * Creates multiple Medical_Record__c records from documents array
     * NEW METHOD FOR DOCUMENT-LEVEL PROCESSING
     *
     * Each document in the array should have full 8-field extraction:
     * {
     *   "sequenceNumber": 1,
     *   "documentType": "ER Report",
     *   "provider": "...",
     *   "dateOfService": "YYYY-MM-DD",
     *   "chiefComplaint": "...",
     *   "pastMedicalHistory": "...",
     *   "treatmentPlan": "...",
     *   "diagnosis": "...",
     *   "nextOfficeVisit": "YYYY-MM-DD",
     *   "workStatus": "Full Duty|Light Duty|Off Work|Unknown"
     * }
     */
    private static List<Medical_Record__c> createMedicalRecordsFromDocuments(
        List<Object> documents,
        Id contentDocumentId,
        Id claimId,
        String uploadBatchId,
        String pdfName,
        String rawJson,
        Map<String, Object> riskAnalysis
    ) {
        List<Medical_Record__c> records = new List<Medical_Record__c>();

        if (documents == null || documents.isEmpty()) {
            return records;
        }

        // Get file checksum for duplicate prevention
        String fileChecksum = getFileChecksum(contentDocumentId);

        // Generate analysis hash for consistency checking
        String analysisHash = generateAnalysisHash(documents);

        // Extract risk analysis data (applies to all documents in this PDF)
        Boolean highRisk = false;
        Integer riskScore = null;
        String highRiskIndicators = null;
        if (riskAnalysis != null) {
            highRisk = riskAnalysis.get('highRisk') == true;
            if (riskAnalysis.get('riskScore') != null) {
                riskScore = Integer.valueOf(riskAnalysis.get('riskScore'));
            }
            List<Object> indicators = (List<Object>) riskAnalysis.get('indicators');
            if (indicators != null && !indicators.isEmpty()) {
                List<String> indicatorStrings = new List<String>();
                for (Object ind : indicators) {
                    indicatorStrings.add(String.valueOf(ind));
                }
                highRiskIndicators = String.join(indicatorStrings, '\n');
            }
        }

        Integer sequence = 0;
        for (Object docObj : documents) {
            Map<String, Object> doc = (Map<String, Object>) docObj;
            sequence++;

            Medical_Record__c record = new Medical_Record__c();

            // Extract all fields for this document
            record.Patient_Name__c = (String) doc.get('patientName');
            record.Date_of_Birth__c = parseDate((String) doc.get('dateOfBirth'));
            record.Provider__c = (String) doc.get('provider');
            record.Referring_Doctor__c = (String) doc.get('referringDoctor');
            record.Reading_Doctor__c = (String) doc.get('readingDoctor');            
            record.Date_of_Service__c = parseDate((String) doc.get('dateOfService'));
            record.Chief_Complaint__c = truncate((String) doc.get('chiefComplaint'), 1000);
            record.Past_Medical_History__c = truncate((String) doc.get('pastMedicalHistory'), 10000);
            record.Treatment_Plan__c = truncate((String) doc.get('treatmentPlan'), 10000);
            record.Diagnosis__c = truncate((String) doc.get('diagnosis'), 1000);
            record.Next_Office_Visit__c = parseDate((String) doc.get('nextOfficeVisit'));
            record.Work_Status__c = normalizeWorkStatus((String) doc.get('workStatus'));
            record.Condition_Progression__c = normalizeConditionProgression((String) doc.get('conditionProgression'));
            record.Summary__c = truncate((String) doc.get('summary'), 2000);

            // Document type (from AI or fallback to sequence)
            String docType = (String) doc.get('documentType');
            record.Document_Type__c = normalizeDocumentType(docType != null ? docType : (String) doc.get('type'));

            // Document sequencing fields
            record.Document_Sequence_Number__c = doc.get('sequenceNumber') != null
                ? Integer.valueOf(doc.get('sequenceNumber'))
                : sequence;
            record.Upload_Batch_ID__c = uploadBatchId;
            record.Source_PDF_Name__c = pdfName;

            // Shared metadata
            record.Content_Document_Id__c = contentDocumentId;
            record.Claims__c = claimId;

            // NEW FIELDS - Duplicate prevention and consistency checking
            record.File_Checksum__c = fileChecksum;
            record.Analysis_Hash__c = analysisHash;
            record.Has_Inconsistent_Analysis__c = false; // Default to false, set during comparison

            // Apply risk analysis to each record (from root-level riskAnalysis)
            record.Requires_Review__c = highRisk;
            record.Risk_Score__c = riskScore;
            record.High_Risk_Indicators__c = highRiskIndicators;

            // Store raw JSON and document listing only on first record to save storage
            if (sequence == 1) {
                record.Raw_JSON__c = truncate(rawJson, 131072);
                record.Document_Listing__c = generateDocumentListingHTML(documents);
            }

            // Generate individual document analysis summary
            record.Analysis_Summary__c = generateDocumentAnalysisSummaryHTML(doc, sequence, documents.size());

            // Document count (how many documents were in the PDF)
            record.Document_Count__c = documents.size();

            records.add(record);
        }

        return records;
    }

    /**
     * Creates single Medical_Record__c from legacy format or single-document PDF
     * BACKWARD COMPATIBILITY METHOD
     */
    private static Medical_Record__c createMedicalRecordLegacy(
        Map<String, Object> parsed,
        Id contentDocumentId,
        Id claimId,
        String uploadBatchId,
        String pdfName,
        String rawJson
    ) {
        Medical_Record__c record = new Medical_Record__c();

        // Determine format: new (nested) or legacy (flat)
        Map<String, Object> extractedData;
        if (parsed.containsKey('extractedData')) {
            // New format with nested structure
            extractedData = (Map<String, Object>) parsed.get('extractedData');
        } else {
            // Legacy flat format - use entire parsed map
            extractedData = parsed;
        }

        // Set standard extracted fields
        record.Patient_Name__c = (String) extractedData.get('patientName');
        record.Date_of_Birth__c = parseDate((String) extractedData.get('dateOfBirth'));
        record.Provider__c = (String) extractedData.get('provider');
        record.Referring_Doctor__c = (String) extractedData.get('referringDoctor');
        record.Reading_Doctor__c = (String) extractedData.get('readingDoctor');
        record.Date_of_Service__c = parseDate((String) extractedData.get('dateOfService'));
        record.Chief_Complaint__c = truncate((String) extractedData.get('chiefComplaint'), 1000);
        record.Past_Medical_History__c = truncate((String) extractedData.get('pastMedicalHistory'), 10000);
        record.Treatment_Plan__c = truncate((String) extractedData.get('treatmentPlan'), 10000);
        record.Diagnosis__c = truncate((String) extractedData.get('diagnosis'), 1000);
        record.Next_Office_Visit__c = parseDate((String) extractedData.get('nextOfficeVisit'));
        record.Work_Status__c = normalizeWorkStatus((String) extractedData.get('workStatus'));
        record.Condition_Progression__c = normalizeConditionProgression((String) extractedData.get('conditionProgression'));
        record.Summary__c = truncate((String) extractedData.get('summary'), 2000);

        // Document type
        record.Document_Type__c = 'Other';
        record.Document_Count__c = 1;

        // NEW sequencing fields
        record.Document_Sequence_Number__c = 1;
        record.Upload_Batch_ID__c = uploadBatchId;
        record.Source_PDF_Name__c = pdfName;

        // Process risk analysis (if present)
        if (parsed.containsKey('riskAnalysis')) {
            Map<String, Object> riskAnalysis = (Map<String, Object>) parsed.get('riskAnalysis');
            record.Requires_Review__c = (Boolean) riskAnalysis.get('highRisk');
            record.Risk_Score__c = (Integer) riskAnalysis.get('riskScore');

            // Join risk indicators into text
            List<Object> indicators = (List<Object>) riskAnalysis.get('indicators');
            if (indicators != null && !indicators.isEmpty()) {
                List<String> indicatorStrings = new List<String>();
                for (Object ind : indicators) {
                    indicatorStrings.add(String.valueOf(ind));
                }
                record.High_Risk_Indicators__c = String.join(indicatorStrings, '\n');
            }
        }

        // Generate comprehensive analysis summary
        record.Analysis_Summary__c = generateAnalysisSummaryHTML(extractedData, parsed);

        // Set metadata fields
        record.Content_Document_Id__c = contentDocumentId;
        record.Claims__c = claimId;
        record.Raw_JSON__c = truncate(rawJson, 131072); // Long Text Area max

        return record;
    }

    /**
     * Parses date string in YYYY-MM-DD format
     * Returns null if parsing fails
     */
    private static Date parseDate(String dateStr) {
        if (String.isBlank(dateStr) || dateStr == 'null') {
            return null;
        }

        try {
            // Expected format: YYYY-MM-DD
            List<String> parts = dateStr.split('-');
            if (parts.size() == 3) {
                Integer year = Integer.valueOf(parts[0]);
                Integer month = Integer.valueOf(parts[1]);
                Integer day = Integer.valueOf(parts[2]);
                return Date.newInstance(year, month, day);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to parse date: ' + dateStr);
        }

        return null;
    }

    /**
     * Truncates text to max length to prevent field length errors
     */
    private static String truncate(String text, Integer maxLength) {
        if (String.isBlank(text)) {
            return null;
        }

        return text.length() > maxLength ? text.substring(0, maxLength) : text;
    }

    /**
     * Normalizes work status to match picklist values
     * Picklist: Full Duty, Light Duty, Off Work, Unknown
     */
    private static String normalizeWorkStatus(String workStatus) {
        if (String.isBlank(workStatus)) {
            return 'Unknown';
        }

        String normalized = workStatus.toLowerCase().trim();

        if (normalized.contains('full')) {
            return 'Full Duty';
        } else if (normalized.contains('light') || normalized.contains('modified')) {
            return 'Light Duty';
        } else if (normalized.contains('off') || normalized.contains('disabled')) {
            return 'Off Work';
        } else {
            return 'Unknown';
        }
    }

    /**
     * Normalizes condition progression to match picklist values
     * Picklist: Improving, Stable, Declining, Unknown
     */
    private static String normalizeConditionProgression(String progression) {
        if (String.isBlank(progression)) {
            return 'Unknown';
        }

        String normalized = progression.toLowerCase().trim();

        if (normalized.contains('improv') || normalized.contains('better') || normalized.contains('healing')) {
            return 'Improving';
        } else if (normalized.contains('declin') || normalized.contains('worse') || normalized.contains('deteriorat')) {
            return 'Declining';
        } else if (normalized.contains('stable') || normalized.contains('unchanged') || normalized.contains('same')) {
            return 'Stable';
        } else {
            return 'Unknown';
        }
    }

    /**
     * Generates HTML table listing all documents found in the PDF
     * Sorted chronologically by date
     */
    private static String generateDocumentListingHTML(List<Object> documents) {
        if (documents == null || documents.isEmpty()) {
            return '<p style="color: #706e6b;">No multiple documents detected</p>';
        }

        String html = '<table style="width:100%; border-collapse:collapse; font-size:12px;">';
        html += '<thead><tr style="background-color:#f3f2f2;">';
        html += '<th style="padding:8px; border:1px solid #d8d8d8; text-align:left;">Date</th>';
        html += '<th style="padding:8px; border:1px solid #d8d8d8; text-align:left;">Type</th>';
        html += '<th style="padding:8px; border:1px solid #d8d8d8; text-align:left;">Provider</th>';
        html += '<th style="padding:8px; border:1px solid #d8d8d8; text-align:left;">Key Findings</th>';
        html += '</tr></thead><tbody>';

        for (Object docObj : documents) {
            Map<String, Object> doc = (Map<String, Object>) docObj;
            html += '<tr>';
            html += '<td style="padding:8px; border:1px solid #d8d8d8;">' + String.valueOf(doc.get('date')) + '</td>';
            html += '<td style="padding:8px; border:1px solid #d8d8d8;">' + String.valueOf(doc.get('type')) + '</td>';
            html += '<td style="padding:8px; border:1px solid #d8d8d8;">' + String.valueOf(doc.get('provider')) + '</td>';
            html += '<td style="padding:8px; border:1px solid #d8d8d8;">' + String.valueOf(doc.get('keyFindings')) + '</td>';
            html += '</tr>';
        }

        html += '</tbody></table>';
        return html;
    }

    /**
     * Determines primary document type based on documents list
     * Returns "Mixed/Multiple" if more than one type
     */
    private static String determinePrimaryDocumentType(List<Object> documents) {
        if (documents == null || documents.isEmpty()) {
            return 'Other';
        }

        if (documents.size() == 1) {
            Map<String, Object> doc = (Map<String, Object>) documents[0];
            return normalizeDocumentType(String.valueOf(doc.get('type')));
        }

        return 'Mixed/Multiple';
    }

    /**
     * Normalizes document type string to match picklist values
     */
    private static String normalizeDocumentType(String docType) {
        if (String.isBlank(docType)) {
            return 'Other';
        }

        String normalized = docType.toLowerCase();

        if (normalized.contains('er') || normalized.contains('emergency')) {
            return 'ER Report';
        } else if (normalized.contains('surgery') || normalized.contains('surgical')) {
            return 'Surgery Notes';
        } else if (normalized.contains('therapy') || normalized.contains('pt')) {
            return 'Physical Therapy';
        } else if (normalized.contains('imaging') || normalized.contains('mri') || normalized.contains('x-ray')) {
            return 'Diagnostic Imaging';
        } else if (normalized.contains('discharge')) {
            return 'Discharge Summary';
        } else if (normalized.contains('progress')) {
            return 'Progress Note';
        } else if (normalized.contains('consult') || normalized.contains('specialist')) {
            return 'Specialist Consult';
        } else if (normalized.contains('lab')) {
            return 'Lab Results';
        } else if (normalized.contains('doctor') || normalized.contains('physician') || normalized.contains('office')) {
            return 'Doctor Visit';
        } else {
            return 'Other';
        }
    }

    /**
     * Generates comprehensive HTML analysis summary for LEGACY format
     * Includes extracted data, document listing, and risk assessment
     */
    private static String generateAnalysisSummaryHTML(Map<String, Object> extractedData, Map<String, Object> fullParsed) {
        String html = '<div style="font-family: Arial, sans-serif; font-size: 13px;">';

        // Section 1: Extracted Medical Data
        html += '<h3 style="color: #16325c; margin-top:0;">Medical Record Summary</h3>';
        html += '<table style="width:100%; border-collapse:collapse;">';
        html += addSummaryRow('Provider', extractedData.get('provider'));
        html += addSummaryRow('Date of Service', extractedData.get('dateOfService'));
        html += addSummaryRow('Chief Complaint', extractedData.get('chiefComplaint'));
        html += addSummaryRow('Diagnosis', extractedData.get('diagnosis'));
        html += addSummaryRow('Treatment Plan', extractedData.get('treatmentPlan'));
        html += addSummaryRow('Work Status', extractedData.get('workStatus'));
        html += addSummaryRow('Next Office Visit', extractedData.get('nextOfficeVisit'));
        html += '</table>';

        // Section 2: Risk Analysis (if present)
        if (fullParsed.containsKey('riskAnalysis')) {
            Map<String, Object> riskAnalysis = (Map<String, Object>) fullParsed.get('riskAnalysis');
            Boolean highRisk = (Boolean) riskAnalysis.get('highRisk');

            html += '<h3 style="color: #16325c; margin-top:20px;">Risk Assessment</h3>';

            if (highRisk == true) {
                html += '<div style="background-color: #fedad8; padding: 12px; border-left: 4px solid #c23934; margin-bottom:10px;">';
                html += '<strong style="color: #c23934;">⚠ HIGH RISK - REVIEW REQUIRED</strong>';
                html += '</div>';
            } else {
                html += '<div style="background-color: #d4edda; padding: 12px; border-left: 4px solid #28a745; margin-bottom:10px;">';
                html += '<strong style="color: #28a745;">✓ Standard Risk</strong>';
                html += '</div>';
            }

            html += '<p><strong>Risk Score:</strong> ' + riskAnalysis.get('riskScore') + '/100</p>';

            List<Object> indicators = (List<Object>) riskAnalysis.get('indicators');
            if (indicators != null && !indicators.isEmpty()) {
                html += '<p><strong>Risk Indicators:</strong></p><ul>';
                for (Object ind : indicators) {
                    html += '<li>' + String.valueOf(ind) + '</li>';
                }
                html += '</ul>';
            }

            html += '<p><strong>Recommendation:</strong> ' + riskAnalysis.get('recommendation') + '</p>';
        }

        html += '</div>';
        return html;
    }

    /**
     * Generates HTML analysis summary for INDIVIDUAL DOCUMENT (new document-level processing)
     * Shows document position in batch and extracted fields
     */
    private static String generateDocumentAnalysisSummaryHTML(Map<String, Object> doc, Integer sequenceNum, Integer totalDocs) {
        String html = '<div style="font-family: Arial, sans-serif; font-size: 13px;">';

        // Document position badge
        html += '<div style="background-color: #f3f2f2; padding: 8px; margin-bottom: 12px; border-radius: 4px;">';
        html += '<strong>Document ' + sequenceNum + ' of ' + totalDocs + '</strong> in this upload';
        html += '</div>';

        // Extracted Medical Data
        html += '<h3 style="color: #16325c; margin-top:0;">Medical Record Details</h3>';
        html += '<table style="width:100%; border-collapse:collapse;">';
        html += addSummaryRow('Document Type', doc.get('documentType'));
        html += addSummaryRow('Provider', doc.get('provider'));
        html += addSummaryRow('Date of Service', doc.get('dateOfService'));
        html += addSummaryRow('Chief Complaint', doc.get('chiefComplaint'));
        html += addSummaryRow('Diagnosis', doc.get('diagnosis'));
        html += addSummaryRow('Treatment Plan', doc.get('treatmentPlan'));
        html += addSummaryRow('Past Medical History', doc.get('pastMedicalHistory'));
        html += addSummaryRow('Work Status', doc.get('workStatus'));
        html += addSummaryRow('Next Office Visit', doc.get('nextOfficeVisit'));
        html += '</table>';

        html += '</div>';
        return html;
    }

    /**
     * Helper to add a row to summary table
     */
    private static String addSummaryRow(String label, Object value) {
        String valueStr = value != null ? String.valueOf(value) : '<span style="color:#706e6b;">Not specified</span>';
        String html = '<tr>';
        html += '<td style="padding:6px; font-weight:bold; width:180px; vertical-align:top;">' + label + ':</td>';
        html += '<td style="padding:6px;">' + valueStr + '</td>';
        html += '</tr>';
        return html;
    }

    /**
     * Publishes Medical_Record_Changed__e Platform Event to notify LWC components
     * This enables auto-refresh of timeline and other components when records change
     *
     * @param claimId - The Claim__c ID associated with the medical records
     * @param recordIds - List of Medical_Record__c IDs that were created/updated
     */
    private static void publishMedicalRecordChangedEvent(Id claimId, List<Id> recordIds) {
        if (claimId == null || recordIds == null || recordIds.isEmpty()) {
            return;
        }

        try {
            List<Medical_Record_Changed__e> events = new List<Medical_Record_Changed__e>();

            for (Id recordId : recordIds) {
                Medical_Record_Changed__e evt = new Medical_Record_Changed__e();
                evt.Claim_Id__c = claimId;
                evt.Record_Id__c = recordId;
                events.add(evt);
            }

            // Publish the events
            List<Database.SaveResult> results = EventBus.publish(events);

            for (Database.SaveResult result : results) {
                if (!result.isSuccess()) {
                    System.debug(LoggingLevel.WARN, 'Failed to publish Medical_Record_Changed__e: ' + result.getErrors());
                }
            }

            System.debug(LoggingLevel.INFO, 'Published ' + events.size() + ' Medical_Record_Changed__e events for Claim: ' + claimId);
        } catch (Exception e) {
            // Don't fail the main transaction if event publishing fails
            System.debug(LoggingLevel.ERROR, 'Error publishing Medical_Record_Changed__e: ' + e.getMessage());
        }
    }

    /**
     * Retrieves the file size of a ContentDocument
     * Used by the cost estimation widget to calculate Flex Credits before processing
     *
     * @param contentDocumentId The ID of the ContentDocument
     * @return Integer file size in bytes
     * @throws AuraHandledException if ContentDocument not found
     */
    @AuraEnabled
    public static Integer getContentDocumentSize(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('ContentDocument ID is required');
        }

        List<ContentVersion> versions = [
            SELECT ContentSize
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            throw new AuraHandledException('ContentVersion not found for ID: ' + contentDocumentId);
        }

        return versions[0].ContentSize;
    }

    /**
     * Sends a large document (>15 MB) to external REST service for splitting
     * The external service should:
     * 1. Download the PDF from Salesforce using the ContentDocumentId
     * 2. Split the PDF into smaller chunks
     * 3. Upload the split files back to Salesforce as new ContentDocuments
     * 4. Return the ContentDocumentIds of the split files
     *
     * @param contentDocumentId The original large document to split
     * @param claimId The parent Claim record ID to link split files to
     * @return List<String> ContentDocumentIds of the split files
     * @throws AuraHandledException if splitting fails
     */
    @AuraEnabled
    public static List<String> splitLargeDocument(Id contentDocumentId, Id claimId) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('ContentDocumentId is required');
        }

        try {
            // Get the ContentVersion for the document
            List<ContentVersion> versions = [
                SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];

            if (versions.isEmpty()) {
                throw new AuraHandledException('Document not found: ' + contentDocumentId);
            }

            ContentVersion cv = versions[0];
            System.debug(LoggingLevel.INFO, 'Sending document for splitting: ' + cv.Title + ' (' + cv.ContentSize + ' bytes)');

            // Validate file size does not exceed 75 MB limit
            if (cv.ContentSize > MAX_ALLOWED_FILE_SIZE) {
                Decimal sizeMB = cv.ContentSize / 1048576.0;
                throw new AuraHandledException('File size (' + sizeMB.setScale(2) + ' MB) exceeds the maximum allowed size of 75 MB. Please upload a smaller file.');
            }

            // Call the external REST service
            List<String> splitFileIds = callSplitService(contentDocumentId, claimId, cv);

            System.debug(LoggingLevel.INFO, 'Received ' + splitFileIds.size() + ' split file IDs from service');
            return splitFileIds;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error splitting document: ' + e.getMessage());
            throw new AuraHandledException('Error splitting large document: ' + e.getMessage());
        }
    }

    /**
     * Sends a large document to the external REST service for ASYNC splitting.
     * MuleSoft now returns an acknowledgment immediately — the actual split result
     * comes back via API_SplitDocUploadCallback when processing is done.
     *
     * Same endpoint as splitLargeDocument but we don't parse the parts array here;
     * we just confirm the request was accepted.
     *
     * @param contentDocumentId The original large document to split
     * @param claimId The parent Claim record ID to link split files to
     * @return String correlationId or contentDocumentId as acknowledgment
     * @throws AuraHandledException if the async request fails
     */
    @AuraEnabled
    public static String splitLargeDocumentAsync(Id contentDocumentId, Id claimId) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('ContentDocumentId is required');
        }

        try {
            // Get the ContentVersion for the document
            List<ContentVersion> versions = [
                SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];

            if (versions.isEmpty()) {
                throw new AuraHandledException('Document not found: ' + contentDocumentId);
            }

            ContentVersion cv = versions[0];
            System.debug(LoggingLevel.INFO, 'Sending document for ASYNC splitting: ' + cv.Title + ' (' + cv.ContentSize + ' bytes)');

            // Validate file size does not exceed 75 MB limit
            if (cv.ContentSize > MAX_ALLOWED_FILE_SIZE) {
                Decimal sizeMB = cv.ContentSize / 1048576.0;
                throw new AuraHandledException('File size (' + sizeMB.setScale(2) + ' MB) exceeds the maximum allowed size of 75 MB. Please upload a smaller file.');
            }

            // Build request body - same format as sync
            Map<String, Object> requestBody = new Map<String, Object>{
                'claimId' => String.valueOf(claimId),
                'documentId' => String.valueOf(contentDocumentId)
            };

            String jsonString = JSON.serialize(requestBody);

            // Use DT_HTTPCallout framework — same integration config, MuleSoft returns fast now
            DT_HTTPCallout.HttpCalloutWrapper httpCalloutWrapperObj = new DT_HTTPCallout.HttpCalloutWrapper();
            httpCalloutWrapperObj.strIntegrationName = DT_Constants.LWCCSPLITPDFSERVICE;
            httpCalloutWrapperObj.strRequestBody = jsonString;
            httpCalloutWrapperObj.endpointExtension = '';
            httpCalloutWrapperObj.headerValue1 = '';
            httpCalloutWrapperObj.headerValue2 = '';
            httpCalloutWrapperObj.headerValue3 = '';
            httpCalloutWrapperObj.headerValue4 = '';

            DT_HTTPCallout httpCalloutObj = new DT_HTTPCallout();
            HttpResponse response = httpCalloutObj.performCallout(httpCalloutWrapperObj);

            System.debug(LoggingLevel.INFO, 'Async split service response status: ' + response.getStatusCode());

            if (response.getStatusCode() == 200 || response.getStatusCode() == 201 || response.getStatusCode() == 202) {
                // Log the async request for tracking
                IntegrationLogManager.createIntegrationLog(
                    'MedicalRecordController',
                    String.valueOf(contentDocumentId) + '_' + String.valueOf(claimId),
                    String.valueOf(claimId),
                    jsonString,
                    response.getBody(),
                    'Async Split Initiated',
                    null
                );

                // try to grab a correlationId from the response, fall back to documentId
                String correlationId = String.valueOf(contentDocumentId);
                try {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                    if (responseMap.containsKey('correlationId') && responseMap.get('correlationId') != null) {
                        correlationId = String.valueOf(responseMap.get('correlationId'));
                    }
                } catch (Exception parseEx) {
                    // response might not be JSON — that's fine, use documentId
                    System.debug(LoggingLevel.WARN, 'Could not parse async response body: ' + parseEx.getMessage());
                }

                System.debug(LoggingLevel.INFO, 'Async split initiated. CorrelationId: ' + correlationId);
                return correlationId;
            } else {
                System.debug(LoggingLevel.ERROR, 'Async split service error: ' + response.getStatusCode() + ' - ' + response.getBody());
                throw new AuraHandledException('Document splitting service returned error: ' + response.getStatusCode() + '. Please try again or contact support.');
            }

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error initiating async split: ' + e.getMessage());
            throw new AuraHandledException('Error initiating async document split: ' + e.getMessage());
        }
    }

    /**
     * Makes the REST callout to the document splitting service
     * Uses DT_HTTPCallout framework with DT_Integration__mdt metadata 'DT_LWCC_SplitPDFService'
     *
     * Expected Response Format:
     * {
     *   "success": true,
     *   "splitFileIds": ["069xxxxxxxxxxxx", "069xxxxxxxxxxxx", ...]
     * }
     * OR
     * {
     *   "success": true,
     *   "files": [{ "contentDocumentId": "069xxxxxxxxxxxx" }, ...]
     * }
     *
     * @param contentDocumentId Original document ID
     * @param claimId Parent claim ID
     * @param cv ContentVersion record with file metadata
     * @return List<String> ContentDocumentIds for split files
     */
    private static List<String> callSplitService(Id contentDocumentId, Id claimId, ContentVersion cv) {
        // Build request body matching the expected API format
        Map<String, Object> requestBody = new Map<String, Object>{
            'claimId' => String.valueOf(claimId),
            'documentId' => String.valueOf(contentDocumentId)
        };

        String jsonString = JSON.serialize(requestBody);

        // Use DT_HTTPCallout framework
        DT_HTTPCallout.HttpCalloutWrapper httpCalloutWrapperObj = new DT_HTTPCallout.HttpCalloutWrapper();
        httpCalloutWrapperObj.strIntegrationName = DT_Constants.LWCCSPLITPDFSERVICE;
        httpCalloutWrapperObj.strRequestBody = jsonString;
        httpCalloutWrapperObj.endpointExtension = '';
        httpCalloutWrapperObj.headerValue1 = '';
        httpCalloutWrapperObj.headerValue2 = '';
        httpCalloutWrapperObj.headerValue3 = '';
        httpCalloutWrapperObj.headerValue4 = '';

        DT_HTTPCallout httpCalloutObj = new DT_HTTPCallout();
        HttpResponse response = httpCalloutObj.performCallout(httpCalloutWrapperObj);

        System.debug(LoggingLevel.INFO, 'Split service response status: ' + response.getStatusCode());

        if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
            return parseSplitServiceResponse(response.getBody());
        } else {
            System.debug(LoggingLevel.ERROR, 'Split service error: ' + response.getStatusCode() + ' - ' + response.getBody());
            throw new AuraHandledException('Document splitting service returned error: ' + response.getStatusCode() + '. Please try again or contact support.');
        }
    }

    /**
     * Parses the response from the split service
     * Extracts contentDocumentId from each part in the parts array
     *
     * Expected Response Format:
     * {
     *   "status": "COMPLETED",
     *   "partCount": 2,
     *   "parts": [
     *     { "partNumber": 1, "contentDocumentId": "069xxxx", ... },
     *     { "partNumber": 2, "contentDocumentId": "069xxxx", ... }
     *   ]
     * }
     *
     * @param responseBody JSON response body
     * @return List<String> ContentDocumentIds for split files
     */
    private static List<String> parseSplitServiceResponse(String responseBody) {
        List<String> splitFileIds = new List<String>();

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        // Check if status is COMPLETED
        String status = (String) responseMap.get('status');
        if (String.isNotBlank(status) && status != 'COMPLETED') {
            throw new AuraHandledException('Document splitting service returned status: ' + status + '. Please try again.');
        }

        // Extract contentDocumentId from each part in the parts array
        if (responseMap.containsKey('parts')) {
            List<Object> parts = (List<Object>) responseMap.get('parts');
            for (Object partObj : parts) {
                Map<String, Object> partMap = (Map<String, Object>) partObj;
                if (partMap.containsKey('contentDocumentId')) {
                    String contentDocId = String.valueOf(partMap.get('contentDocumentId'));
                    // Avoid duplicates (in case same contentDocumentId appears multiple times)
                    if (!splitFileIds.contains(contentDocId)) {
                        splitFileIds.add(contentDocId);
                    }
                }
            }
        }

        if (splitFileIds.isEmpty()) {
            throw new AuraHandledException('No split file IDs returned from document splitting service. Please verify the service configuration.');
        }

        System.debug(LoggingLevel.INFO, 'Parsed ' + splitFileIds.size() + ' unique contentDocumentIds from response');
        return splitFileIds;
    }

    /**
     * Extracts totalPages from the AI response metadata
     * Safely handles missing or null metadata
     *
     * @param parsed - Parsed JSON response from AI
     * @return Integer - Page count from AI, or null if not available
     */
    private static Integer extractTotalPages(Map<String, Object> parsed) {
        try {
            if (parsed == null || !parsed.containsKey('metadata')) {
                return null;
            }

            Map<String, Object> metadata = (Map<String, Object>) parsed.get('metadata');
            if (metadata == null || !metadata.containsKey('totalPages')) {
                return null;
            }

            Object totalPagesObj = metadata.get('totalPages');
            if (totalPagesObj instanceof Integer) {
                return (Integer) totalPagesObj;
            } else if (totalPagesObj instanceof Decimal) {
                return ((Decimal) totalPagesObj).intValue();
            } else if (totalPagesObj instanceof String) {
                return Integer.valueOf((String) totalPagesObj);
            }

            return null;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to extract totalPages from metadata: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Regenerates the Summary field for a medical record using AI
     * Uses existing field data (diagnosis, treatment plan, etc.) instead of re-processing the PDF
     *
     * @param medicalRecordId - Medical_Record__c ID to regenerate summary for
     * @return Medical_Record__c - Updated record with new summary
     */
    @AuraEnabled
    public static Medical_Record__c regenerateSummaryFromRecord(Id medicalRecordId) {
        System.debug(LoggingLevel.INFO, '=== START: regenerateSummaryFromRecord ===');
        System.debug(LoggingLevel.INFO, 'MedicalRecordId: ' + medicalRecordId);

        try {
            // Step 1: Get existing record
            Medical_Record__c existing = getMedicalRecordById(medicalRecordId);

            // Step 2: Build prompt context from existing fields
            String promptContext = buildSummaryPromptContext(existing);
            System.debug(LoggingLevel.INFO, 'Prompt context length: ' + promptContext.length());

            // Step 3: Call AI to generate new summary
            String newSummary = generateSummaryFromContext(promptContext);
            System.debug(LoggingLevel.INFO, 'Generated summary length: ' + (newSummary != null ? newSummary.length() : 0));

            // Step 4: Update the record with new summary
            if (!Schema.sObjectType.Medical_Record__c.isUpdateable()) {
                throw new AuraHandledException('Insufficient permissions to update Medical Records');
            }

            Medical_Record__c recordToUpdate = new Medical_Record__c();
            recordToUpdate.Id = medicalRecordId;
            recordToUpdate.Summary__c = truncate(newSummary, 2000);

            update recordToUpdate;
            System.debug(LoggingLevel.INFO, 'Successfully updated summary for record: ' + medicalRecordId);

            // Step 5: Return updated record
            System.debug(LoggingLevel.INFO, '=== END: regenerateSummaryFromRecord - SUCCESS ===');
            return getMedicalRecordById(medicalRecordId);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '=== EXCEPTION in regenerateSummaryFromRecord ===');
            System.debug(LoggingLevel.ERROR, 'Error Message: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Failed to regenerate summary: ' + e.getMessage());
        }
    }

    /**
     * Builds a prompt context string from existing medical record fields
     * Used for regenerating summary without re-processing PDF
     */
    public static String buildSummaryPromptContext(Medical_Record__c record) {
        List<String> contextParts = new List<String>();

        if (String.isNotBlank(record.Document_Type__c)) {
            contextParts.add('Document Type: ' + record.Document_Type__c);
        }
        if (String.isNotBlank(record.Patient_Name__c)) {
            contextParts.add('Patient: ' + record.Patient_Name__c);
        }
        if (record.Date_of_Service__c != null) {
            contextParts.add('Date of Service: ' + String.valueOf(record.Date_of_Service__c));
        }
        if (String.isNotBlank(record.Provider__c)) {
            contextParts.add('Provider: ' + record.Provider__c);
        }
        if (String.isNotBlank(record.Chief_Complaint__c)) {
            contextParts.add('Chief Complaint: ' + record.Chief_Complaint__c);
        }
        if (String.isNotBlank(record.Diagnosis__c)) {
            contextParts.add('Diagnosis: ' + record.Diagnosis__c);
        }
        if (String.isNotBlank(record.Treatment_Plan__c)) {
            contextParts.add('Treatment Plan: ' + record.Treatment_Plan__c);
        }
        if (String.isNotBlank(record.Work_Status__c)) {
            contextParts.add('Work Status: ' + record.Work_Status__c);
        }
        if (record.Next_Office_Visit__c != null) {
            contextParts.add('Next Office Visit: ' + String.valueOf(record.Next_Office_Visit__c));
        }
        if (String.isNotBlank(record.Past_Medical_History__c)) {
            contextParts.add('Past Medical History: ' + record.Past_Medical_History__c);
        }

        return String.join(contextParts, '\n');
    }

    /**
     * Generates a summary from the provided context using Einstein AI
     * Uses a text-based prompt template for summary generation
     */
    public static String generateSummaryFromContext(String context) {
        try {
            // Build Prompt Builder input for summary generation
            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.isPreview = false;
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            input.additionalConfig.numGenerations = 1;
            input.additionalConfig.temperature = 0;

            // Create input parameters map with the context
            Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();

            ConnectApi.WrappedValue contextValue = new ConnectApi.WrappedValue();
            contextValue.value = context;
            valueMap.put('Input:Medical_Record_Context', contextValue);

            input.inputParams = valueMap;

            // Call the summary regeneration template
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    'Medical_Record_Summary_Generator',
                    input
                );

            if (result.generations != null && !result.generations.isEmpty()) {
                return result.generations[0].text;
            } else {
                throw new AuraHandledException('No summary generated from AI');
            }

        } catch (ConnectApi.ConnectApiException e) {
            System.debug(LoggingLevel.ERROR, 'Prompt Builder error: ' + e.getMessage());
            // Fallback: Generate a basic summary from the context
            return generateFallbackSummary(context);
        }
    }

    /**
     * Generates a basic fallback summary when AI is unavailable
     */
    public static String generateFallbackSummary(String context) {
        // Parse the context and create a simple summary
        return 'Medical record summary generated from existing data. ' +
               'Please review the full record details for complete information.';
    }

    /**
     * Reanalyzes all Medical Records for a given Claim (Async)
     * Queues a background job to regenerate summaries from existing record data
     * Does NOT re-process PDFs - only regenerates text summaries
     *
     * @param claimId - The Claim__c record ID
     * @return Map<String, Object> - Status indicating job was queued with record count
     */
    @AuraEnabled
    public static Map<String, Object> reanalyzeAllMedicalRecords(Id claimId) {
        System.debug(LoggingLevel.INFO, '=== START: reanalyzeAllMedicalRecords (Async) ===');
        System.debug(LoggingLevel.INFO, 'ClaimId: ' + claimId);

        try {
            if (claimId == null) {
                throw new AuraHandledException('Claim ID is required');
            }

            // Step 1: Get all Medical Record IDs for this claim
            List<Medical_Record__c> records = [
                SELECT Id
                FROM Medical_Record__c
                WHERE Claims__c = :claimId
                ORDER BY Date_of_Service__c DESC
                LIMIT 200
            ];

            System.debug(LoggingLevel.INFO, 'Found ' + records.size() + ' medical records to reanalyze');

            if (records.isEmpty()) {
                throw new AuraHandledException('No medical records found for this claim');
            }

            // Step 2: Collect record IDs
            List<Id> recordIds = new List<Id>();
            for (Medical_Record__c record : records) {
                recordIds.add(record.Id);
            }

            // Step 3: Enqueue the Queueable job for async processing
            Id jobId = System.enqueueJob(new ReanalyzeMedicalRecordsQueueable(claimId, recordIds));
            System.debug(LoggingLevel.INFO, 'Enqueued reanalysis job with ID: ' + jobId);

            // Step 4: Return status response
            Map<String, Object> response = new Map<String, Object>();
            response.put('status', 'QUEUED');
            response.put('jobId', jobId);
            response.put('recordCount', records.size());
            response.put('message', 'Reanalysis job started for ' + records.size() + ' medical records. Summaries will be regenerated in the background.');

            System.debug(LoggingLevel.INFO, '=== END: reanalyzeAllMedicalRecords - Job Queued ===');
            return response;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '=== EXCEPTION in reanalyzeAllMedicalRecords ===');
            System.debug(LoggingLevel.ERROR, 'Error Message: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Failed to start reanalysis: ' + e.getMessage());
        }
    }

    /**
     * Wrapper class for analyze Medical Record response
     * Contains both the medical records and metadata (including page count)
     */
    public class AnalysisResponse {
        @AuraEnabled public List<Medical_Record__c> documents;
        @AuraEnabled public AnalysisMetadata metadata;

        public AnalysisResponse(List<Medical_Record__c> documents, AnalysisMetadata metadata) {
            this.documents = documents;
            this.metadata = metadata;
        }
    }

    /**
     * Metadata from AI analysis response
     */
    public class AnalysisMetadata {
        @AuraEnabled public Integer totalPages;
        @AuraEnabled public Integer totalDocuments;

        public AnalysisMetadata(Integer totalPages, Integer totalDocuments) {
            this.totalPages = totalPages;
            this.totalDocuments = totalDocuments;
        }
    }

    /**
     * Inner class that runs without sharing to bypass visibility restrictions
     * on ContentWorkspace, ContentFolder, GroupMember, and related objects.
     */
    private without sharing class ElevatedAccess {

        public void updateGroupMembership(String groupName, Id userId) {
            try {
                List<Group> groups = [
                    SELECT Id FROM Group
                    WHERE Name = :groupName AND Type = 'Regular'
                    LIMIT 1
                ];
                if (groups.isEmpty()) {
                    System.debug(LoggingLevel.WARN, 'Public group not found: ' + groupName);
                    return;
                }
                Id groupId = groups[0].Id;

                // Remove other members (keep current user to avoid sharing recalculation gap)
                List<GroupMember> existingMembers = [
                    SELECT Id, UserOrGroupId FROM GroupMember WHERE GroupId = :groupId
                ];
                Boolean currentUserAlreadyMember = false;
                List<GroupMember> membersToDelete = new List<GroupMember>();
                for (GroupMember gm : existingMembers) {
                    if (gm.UserOrGroupId == userId) {
                        currentUserAlreadyMember = true;
                    } else {
                        membersToDelete.add(gm);
                    }
                }
                if (!membersToDelete.isEmpty()) {
                    delete membersToDelete;
                }

                // Add running user only if not already a member
                if (!currentUserAlreadyMember) {
                    GroupMember newMember = new GroupMember();
                    newMember.GroupId = groupId;
                    newMember.UserOrGroupId = userId;
                    insert newMember;
                }
                System.debug(LoggingLevel.INFO, 'Updated group membership: user ' + userId + ' is member of ' + groupName);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Error updating group membership: ' + e.getMessage());
            }
        }

        public void addFileToLibraryAndOrganize(String libraryName, Id contentDocumentId, Id claimId) {
            List<ContentWorkspace> workspaces = [
                SELECT Id, RootContentFolderId
                FROM ContentWorkspace
                WHERE Name = :libraryName
                LIMIT 1
            ];

            if (workspaces.isEmpty()) {
                throw new AuraHandledException(
                    'Content Library "' + libraryName + '" not found. ' +
                    'Please ask your Salesforce administrator to create this library in Setup > Content Libraries.'
                );
            }

            Id workspaceId = workspaces[0].Id;
            Id rootFolderId = workspaces[0].RootContentFolderId;

            // Add file to the library (prevent duplicates)
            List<ContentWorkspaceDoc> existingDocs = [
                SELECT Id
                FROM ContentWorkspaceDoc
                WHERE ContentDocumentId = :contentDocumentId
                AND ContentWorkspaceId = :workspaceId
                LIMIT 1
            ];

            if (existingDocs.isEmpty()) {
                ContentWorkspaceDoc workspaceDoc = new ContentWorkspaceDoc();
                workspaceDoc.ContentDocumentId = contentDocumentId;
                workspaceDoc.ContentWorkspaceId = workspaceId;
                insert workspaceDoc;
                System.debug(LoggingLevel.INFO, 'File added to Content Library: ' + contentDocumentId);
            }

            // Organize file into claim-number folder
            if (claimId != null && rootFolderId != null) {
                try {
                    organizeFileInClaimFolder(contentDocumentId, claimId, rootFolderId);
                } catch (Exception folderEx) {
                    System.debug(LoggingLevel.ERROR, 'Could not organize file into claim folder: ' + folderEx.getMessage());
                }
            }
        }

        private void organizeFileInClaimFolder(Id contentDocumentId, Id claimId, Id rootFolderId) {
            List<Claim> claims = [SELECT Name FROM Claim WHERE Id = :claimId LIMIT 1];
            if (claims.isEmpty() || String.isBlank(claims[0].Name)) {
                System.debug(LoggingLevel.WARN, 'Could not find claim number for claim: ' + claimId);
                return;
            }
            String claimNumber = claims[0].Name;

            Id claimFolderId = findOrCreateClaimFolder(claimNumber, rootFolderId);

            List<ContentFolderMember> members = [
                SELECT Id, ParentContentFolderId
                FROM ContentFolderMember
                WHERE ChildRecordId = :contentDocumentId
                LIMIT 1
            ];
            if (!members.isEmpty()) {
                members[0].ParentContentFolderId = claimFolderId;
                update members;
                System.debug(LoggingLevel.INFO, 'Moved file to claim folder: ' + claimNumber);
            } else {
                System.debug(LoggingLevel.WARN, 'ContentFolderMember not found for document: ' + contentDocumentId);
            }
        }

        private Id findOrCreateClaimFolder(String claimNumber, Id rootFolderId) {
            List<ContentFolder> existing = [
                SELECT Id FROM ContentFolder
                WHERE Name = :claimNumber
                AND ParentContentFolderId = :rootFolderId
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0].Id;
            }
            ContentFolder newFolder = new ContentFolder();
            newFolder.Name = claimNumber;
            newFolder.ParentContentFolderId = rootFolderId;
            insert newFolder;
            System.debug(LoggingLevel.INFO, 'Created claim folder: ' + claimNumber);
            return newFolder.Id;
        }
    }
}