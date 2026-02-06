package com.lwcc.pdf;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.util.Date;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Helper class to download file content from Salesforce REST API.
 * Features token caching for fast repeated downloads.
 */
public class SalesforceFileDownloader {

    private static final Logger LOGGER = LoggerFactory.getLogger(SalesforceFileDownloader.class);
    private static final int BUFFER_SIZE = 65536; // 64KB for faster reads
    private static final int CONNECTION_TIMEOUT = 10000; // 10 seconds
    private static final int READ_TIMEOUT = 300000; // 5 minutes for large files

    // Token cache: key = principal, value = [accessToken, instanceUrl, expiryTime]
    private static final ConcurrentHashMap<String, String[]> tokenCache = new ConcurrentHashMap<>();
    private static final long TOKEN_CACHE_MS = 240000; // 4 minutes (tokens valid 5 min)

    /**
     * Downloads file content from Salesforce using the REST API and streams to a temporary file.
     * OPTIMIZED VERSION: Streams directly to disk to avoid loading large files into memory.
     *
     * @param instanceUrl The Salesforce instance URL
     * @param accessToken The OAuth access token
     * @param contentVersionId The ContentVersion record ID
     * @return File object pointing to the downloaded content
     * @throws Exception if download fails
     */
    public static File downloadFileToTemp(String instanceUrl, String accessToken, String contentVersionId) throws Exception {
        String downloadUrl = instanceUrl + "/services/data/v59.0/sobjects/ContentVersion/" + contentVersionId + "/VersionData";

        URL url = new URL(downloadUrl);
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();

        try {
            connection.setRequestMethod("GET");
            connection.setRequestProperty("Authorization", "Bearer " + accessToken);
            connection.setRequestProperty("Accept", "application/octet-stream");
            connection.setConnectTimeout(CONNECTION_TIMEOUT);
            connection.setReadTimeout(READ_TIMEOUT);

            int responseCode = connection.getResponseCode();

            if (responseCode != 200) {
                String errorMessage = "HTTP " + responseCode;
                try (InputStream errorStream = connection.getErrorStream()) {
                    if (errorStream != null) {
                        byte[] errorBytes = readAllBytes(errorStream);
                        errorMessage += ": " + new String(errorBytes, "UTF-8");
                    }
                }
                LOGGER.error("DOWNLOAD_FAIL | {}", errorMessage);
                throw new RuntimeException("Download failed: " + errorMessage);
            }

            // Validate Content-Type header
            String contentType = connection.getContentType();
            LOGGER.info("DOWNLOAD_HEADERS | Content-Type: {}", contentType);

            if (contentType != null && !contentType.startsWith("application/") && !contentType.startsWith("binary/")) {
                LOGGER.error("DOWNLOAD_ERROR | Invalid Content-Type: {} | Expected application/* or binary/*", contentType);
                throw new RuntimeException("Download failed: Salesforce returned Content-Type '" + contentType +
                    "' instead of binary content. This usually indicates an HTML error page or session expiration.");
            }

            // Get expected content length
            long contentLength = connection.getContentLengthLong();
            LOGGER.info("DOWNLOAD_HEADERS | Content-Length: {} bytes ({} MB)",
                contentLength, String.format("%.2f", contentLength / 1048576.0));

            // Stream directly to temp file (avoid memory allocation)
            Path tempFile = Files.createTempFile("sf-download-", ".pdf");
            LOGGER.info("DOWNLOAD_STREAM | Streaming to temp file: {}", tempFile.toString());

            long totalBytes = 0;
            long startTime = System.currentTimeMillis();

            try (InputStream inputStream = connection.getInputStream();
                 FileOutputStream outputStream = new FileOutputStream(tempFile.toFile())) {

                byte[] buffer = new byte[BUFFER_SIZE];
                int bytesRead;

                while ((bytesRead = inputStream.read(buffer)) != -1) {
                    outputStream.write(buffer, 0, bytesRead);
                    totalBytes += bytesRead;
                }
            }

            // Validate downloaded size matches Content-Length
            if (contentLength > 0 && totalBytes != contentLength) {
                LOGGER.error("DOWNLOAD_ERROR | Size mismatch: downloaded {} bytes but Content-Length was {} bytes",
                    totalBytes, contentLength);
                throw new RuntimeException("Download incomplete: Downloaded " + totalBytes +
                    " bytes but expected " + contentLength + " bytes");
            }

            // Validate minimum PDF size (PDF header is at least 9 bytes: "%PDF-1.x")
            if (totalBytes < 9) {
                LOGGER.error("DOWNLOAD_ERROR | File too small: {} bytes (minimum PDF is 9 bytes)", totalBytes);
                throw new RuntimeException("Downloaded file is too small to be a valid PDF: " + totalBytes + " bytes");
            }

            long duration = System.currentTimeMillis() - startTime;
            double sizeMB = totalBytes / 1048576.0;
            double throughputMBps = sizeMB / (duration / 1000.0);

            LOGGER.info("DOWNLOAD_COMPLETE | {} MB in {} ms ({} MB/s)",
                    String.format("%.2f", sizeMB),
                    duration,
                    String.format("%.2f", throughputMBps));

            return tempFile.toFile();

        } finally {
            connection.disconnect();
        }
    }

    /**
     * Downloads file content from Salesforce using the REST API.
     * LEGACY METHOD: Loads entire file into memory. Use downloadFileToTemp() for better performance.
     *
     * @param instanceUrl The Salesforce instance URL (e.g., "https://lwcc--dev01.sandbox.my.salesforce.com")
     * @param accessToken The OAuth access token
     * @param contentVersionId The ContentVersion record ID
     * @return byte array containing the file content
     * @throws Exception if download fails
     * @deprecated Use downloadFileToTemp() to avoid memory issues with large files
     */
    @Deprecated
    public static byte[] downloadFile(String instanceUrl, String accessToken, String contentVersionId) throws Exception {
        String downloadUrl = instanceUrl + "/services/data/v59.0/sobjects/ContentVersion/" + contentVersionId + "/VersionData";

        URL url = new URL(downloadUrl);
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();

        try {
            connection.setRequestMethod("GET");
            connection.setRequestProperty("Authorization", "Bearer " + accessToken);
            connection.setRequestProperty("Accept", "application/octet-stream");
            connection.setConnectTimeout(CONNECTION_TIMEOUT);
            connection.setReadTimeout(READ_TIMEOUT);

            int responseCode = connection.getResponseCode();

            if (responseCode != 200) {
                String errorMessage = "HTTP " + responseCode;
                try (InputStream errorStream = connection.getErrorStream()) {
                    if (errorStream != null) {
                        byte[] errorBytes = readAllBytes(errorStream);
                        errorMessage += ": " + new String(errorBytes, "UTF-8");
                    }
                }
                LOGGER.error("DOWNLOAD_FAIL | {}", errorMessage);
                throw new RuntimeException("Download failed: " + errorMessage);
            }

            // Read binary content with large buffer for speed
            try (InputStream inputStream = connection.getInputStream();
                 ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {

                byte[] buffer = new byte[BUFFER_SIZE];
                int bytesRead;

                while ((bytesRead = inputStream.read(buffer)) != -1) {
                    outputStream.write(buffer, 0, bytesRead);
                }

                return outputStream.toByteArray();
            }

        } finally {
            connection.disconnect();
        }
    }

    /**
     * Downloads file content using connection info map from Mule flow.
     *
     * @param connectionInfo Map containing instanceUrl and accessToken
     * @param contentVersionId The ContentVersion record ID
     * @return byte array containing the file content
     * @throws Exception if download fails
     */
    public static byte[] downloadFileWithConnectionInfo(Map<String, Object> connectionInfo, String contentVersionId) throws Exception {
        String instanceUrl = (String) connectionInfo.get("instanceUrl");
        String accessToken = (String) connectionInfo.get("accessToken");

        if (instanceUrl == null || instanceUrl.isEmpty()) {
            throw new IllegalArgumentException("instanceUrl is required");
        }
        if (accessToken == null || accessToken.isEmpty()) {
            throw new IllegalArgumentException("accessToken is required");
        }

        return downloadFile(instanceUrl, accessToken, contentVersionId);
    }

    private static byte[] readAllBytes(InputStream inputStream) throws Exception {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        byte[] data = new byte[1024];
        int bytesRead;
        while ((bytesRead = inputStream.read(data, 0, data.length)) != -1) {
            buffer.write(data, 0, bytesRead);
        }
        return buffer.toByteArray();
    }

    /**
     * Downloads file content from Salesforce using JWT Bearer authentication.
     * OPTIMIZED VERSION: Streams directly to temp file.
     *
     * @param tokenEndpoint The Salesforce OAuth token endpoint
     * @param consumerKey The connected app consumer key
     * @param principal The Salesforce username
     * @param keystorePath Path to the JKS keystore file
     * @param keystorePassword Password for the keystore
     * @param alias Certificate alias in the keystore
     * @param contentVersionId The ContentVersion record ID to download
     * @return File object containing the downloaded content
     * @throws Exception if any step fails
     */
    public static File downloadFileToTempWithJwt(
            String tokenEndpoint,
            String consumerKey,
            String principal,
            String keystorePath,
            String keystorePassword,
            String alias,
            String contentVersionId) throws Exception {

        // Get cached token or fetch new one
        String[] tokenInfo = getCachedToken(tokenEndpoint, consumerKey, principal,
                                            keystorePath, keystorePassword, alias);
        String accessToken = tokenInfo[0];
        String instanceUrl = tokenInfo[1];

        // Download file using the token (streaming)
        return downloadFileToTemp(instanceUrl, accessToken, contentVersionId);
    }

    /**
     * Downloads file content from Salesforce using JWT Bearer authentication.
     * DATAWEAVE-FRIENDLY VERSION: Returns file path as String to avoid type conversion issues.
     *
     * @param tokenEndpoint The Salesforce OAuth token endpoint
     * @param consumerKey The connected app consumer key
     * @param principal The Salesforce username
     * @param keystorePath Path to the JKS keystore file
     * @param keystorePassword Password for the keystore
     * @param alias Certificate alias in the keystore
     * @param contentVersionId The ContentVersion record ID to download
     * @return String path to the downloaded temp file
     * @throws Exception if any step fails
     */
    public static String downloadFileToTempWithJwtReturnPath(
            String tokenEndpoint,
            String consumerKey,
            String principal,
            String keystorePath,
            String keystorePassword,
            String alias,
            String contentVersionId) throws Exception {

        // Call existing method to get File object
        File tempFile = downloadFileToTempWithJwt(tokenEndpoint, consumerKey, principal,
                                                   keystorePath, keystorePassword, alias,
                                                   contentVersionId);

        // Return absolute path as String (avoids DataWeave type conversion issues)
        return tempFile.getAbsolutePath();
    }

    /**
     * Helper method to read file bytes from a file path string.
     * DATAWEAVE-FRIENDLY: Avoids Path type conversion issues in DataWeave.
     *
     * @param filePath The absolute file path as String
     * @return byte array containing the file content
     * @throws Exception if read fails
     */
    public static byte[] readFileBytes(String filePath) throws Exception {
        File file = new File(filePath);
        return Files.readAllBytes(file.toPath());
    }

    /**
     * Helper method to delete a file by path string.
     * DATAWEAVE-FRIENDLY: Avoids Path type conversion issues in DataWeave.
     *
     * @param filePath The absolute file path as String
     * @return true if file was deleted, false if it didn't exist
     * @throws Exception if delete fails
     */
    public static boolean deleteFile(String filePath) throws Exception {
        if (filePath == null || filePath.isEmpty()) {
            return false;
        }
        File file = new File(filePath);
        return Files.deleteIfExists(file.toPath());
    }

    /**
     * Downloads file content from Salesforce using JWT Bearer authentication.
     * LEGACY METHOD: Loads entire file into memory.
     *
     * @deprecated Use downloadFileToTempWithJwt() for better performance
     */
    @Deprecated
    public static byte[] downloadFileWithJwt(
            String tokenEndpoint,
            String consumerKey,
            String principal,
            String keystorePath,
            String keystorePassword,
            String alias,
            String contentVersionId) throws Exception {

        // Get cached token or fetch new one
        String[] tokenInfo = getCachedToken(tokenEndpoint, consumerKey, principal,
                                            keystorePath, keystorePassword, alias);
        String accessToken = tokenInfo[0];
        String instanceUrl = tokenInfo[1];

        // Download file using the token
        return downloadFile(instanceUrl, accessToken, contentVersionId);
    }

    /**
     * Gets Salesforce access token and instance URL for use in callbacks.
     * DATAWEAVE-FRIENDLY: Returns a Map that DataWeave can easily consume.
     *
     * @param tokenEndpoint The Salesforce OAuth token endpoint
     * @param consumerKey The connected app consumer key
     * @param principal The Salesforce username
     * @param keystorePath Path to the JKS keystore file
     * @param keystorePassword Password for the keystore
     * @param alias Certificate alias in the keystore
     * @return Map containing "accessToken" and "instanceUrl"
     * @throws Exception if token retrieval fails
     */
    public static Map<String, String> getTokenInfo(
            String tokenEndpoint,
            String consumerKey,
            String principal,
            String keystorePath,
            String keystorePassword,
            String alias) throws Exception {

        String[] tokenInfo = getCachedToken(tokenEndpoint, consumerKey, principal,
                                            keystorePath, keystorePassword, alias);

        Map<String, String> result = new java.util.HashMap<>();
        result.put("accessToken", tokenInfo[0]);
        result.put("instanceUrl", tokenInfo[1]);
        return result;
    }

    /**
     * Gets token from cache or fetches new one if expired.
     */
    private static String[] getCachedToken(
            String tokenEndpoint,
            String consumerKey,
            String principal,
            String keystorePath,
            String keystorePassword,
            String alias) throws Exception {

        String cacheKey = principal;
        String[] cached = tokenCache.get(cacheKey);

        // Check if cached token is still valid
        if (cached != null && cached.length == 3) {
            long expiryTime = Long.parseLong(cached[2]);
            if (System.currentTimeMillis() < expiryTime) {
                return new String[] { cached[0], cached[1] };
            }
        }

        // Need new token
        LOGGER.info("TOKEN | Fetching new access token...");

        String jwtAssertion = generateJwtAssertion(consumerKey, principal, tokenEndpoint,
                                                    keystorePath, keystorePassword, alias);
        String[] tokenResponse = exchangeJwtForToken(tokenEndpoint, jwtAssertion);

        // Cache the token for 4 minutes
        long expiryTime = System.currentTimeMillis() + TOKEN_CACHE_MS;
        tokenCache.put(cacheKey, new String[] { tokenResponse[0], tokenResponse[1], String.valueOf(expiryTime) });

        LOGGER.info("TOKEN | Cached for {} seconds", TOKEN_CACHE_MS / 1000);
        return tokenResponse;
    }

    /**
     * Generates a JWT assertion for Salesforce OAuth.
     */
    private static String generateJwtAssertion(
            String consumerKey,
            String principal,
            String tokenEndpoint,
            String keystorePath,
            String keystorePassword,
            String alias) throws Exception {

        // Determine audience from token endpoint
        String audience;
        if (tokenEndpoint.contains("test.salesforce.com")) {
            audience = "https://test.salesforce.com";
        } else {
            audience = "https://login.salesforce.com";
        }

        // Load private key from keystore
        KeyStore keyStore = KeyStore.getInstance("JKS");
        try (FileInputStream fis = new FileInputStream(keystorePath)) {
            keyStore.load(fis, keystorePassword.toCharArray());
        }
        PrivateKey privateKey = (PrivateKey) keyStore.getKey(alias, keystorePassword.toCharArray());

        if (privateKey == null) {
            throw new RuntimeException("Private key not found in keystore with alias: " + alias);
        }

        // Build JWT with 5 minute expiration
        long now = System.currentTimeMillis();
        return Jwts.builder()
            .setIssuer(consumerKey)
            .setSubject(principal)
            .setAudience(audience)
            .setExpiration(new Date(now + 300000))
            .signWith(privateKey, SignatureAlgorithm.RS256)
            .compact();
    }

    /**
     * Exchanges a JWT assertion for an access token.
     * @return String array: [0] = access_token, [1] = instance_url
     */
    private static String[] exchangeJwtForToken(String tokenEndpoint, String jwtAssertion) throws Exception {
        URL url = new URL(tokenEndpoint);
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();

        try {
            connection.setRequestMethod("POST");
            connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");
            connection.setDoOutput(true);
            connection.setConnectTimeout(CONNECTION_TIMEOUT);
            connection.setReadTimeout(CONNECTION_TIMEOUT);

            // Build request body
            String requestBody = "grant_type=" + URLEncoder.encode("urn:ietf:params:oauth:grant-type:jwt-bearer", "UTF-8")
                               + "&assertion=" + URLEncoder.encode(jwtAssertion, "UTF-8");

            // Write request body
            try (DataOutputStream out = new DataOutputStream(connection.getOutputStream())) {
                out.writeBytes(requestBody);
                out.flush();
            }

            int responseCode = connection.getResponseCode();
            LOGGER.info("DOWNLOAD_JWT | OAuth response code: {}", responseCode);

            if (responseCode != 200) {
                String errorMessage = "OAuth token exchange failed. HTTP " + responseCode;
                try (InputStream errorStream = connection.getErrorStream()) {
                    if (errorStream != null) {
                        byte[] errorBytes = readAllBytes(errorStream);
                        errorMessage += ": " + new String(errorBytes, "UTF-8");
                    }
                }
                LOGGER.error("DOWNLOAD_JWT | OAuth error: {}", errorMessage);
                throw new RuntimeException(errorMessage);
            }

            // Read response
            String responseBody;
            try (InputStream inputStream = connection.getInputStream()) {
                byte[] responseBytes = readAllBytes(inputStream);
                responseBody = new String(responseBytes, "UTF-8");
            }

            // Parse JSON response (simple parsing without external library)
            String accessToken = extractJsonValue(responseBody, "access_token");
            String instanceUrl = extractJsonValue(responseBody, "instance_url");

            if (accessToken == null || accessToken.isEmpty()) {
                throw new RuntimeException("No access_token in OAuth response: " + responseBody);
            }
            if (instanceUrl == null || instanceUrl.isEmpty()) {
                throw new RuntimeException("No instance_url in OAuth response: " + responseBody);
            }

            return new String[] { accessToken, instanceUrl };

        } finally {
            connection.disconnect();
        }
    }

    /**
     * Simple JSON value extractor (avoids external JSON library dependency).
     */
    private static String extractJsonValue(String json, String key) {
        String searchKey = "\"" + key + "\"";
        int keyIndex = json.indexOf(searchKey);
        if (keyIndex == -1) return null;

        int colonIndex = json.indexOf(":", keyIndex);
        if (colonIndex == -1) return null;

        int startIndex = json.indexOf("\"", colonIndex) + 1;
        if (startIndex == 0) return null;

        int endIndex = json.indexOf("\"", startIndex);
        if (endIndex == -1) return null;

        return json.substring(startIndex, endIndex);
    }

    /**
     * Converts first N bytes to hex string for debugging.
     *
     * @param bytes The byte array
     * @param maxBytes Maximum number of bytes to convert (default 32)
     * @return Hex string representation
     */
    private static String bytesToHex(byte[] bytes, int maxBytes) {
        if (bytes == null || bytes.length == 0) {
            return "(empty)";
        }

        int length = Math.min(bytes.length, maxBytes);
        StringBuilder hex = new StringBuilder(length * 3);

        for (int i = 0; i < length; i++) {
            if (i > 0) hex.append(" ");
            hex.append(String.format("%02X", bytes[i]));
        }

        if (bytes.length > maxBytes) {
            hex.append(" ... (").append(bytes.length - maxBytes).append(" more)");
        }

        return hex.toString();
    }

    /**
     * Public method to get hex dump of file for diagnostics.
     * Can be called from DataWeave for logging.
     *
     * @param filePath The file path to read
     * @param maxBytes Maximum number of bytes to dump
     * @return Hex string representation of first maxBytes
     * @throws Exception if file read fails
     */
    public static String getFileHexDump(String filePath, int maxBytes) throws Exception {
        byte[] bytes = readFileBytes(filePath);
        return bytesToHex(bytes, maxBytes);
    }
}
