package com.lwcc.pdf;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDResources;
import org.apache.pdfbox.pdmodel.graphics.PDXObject;
import org.apache.pdfbox.pdmodel.graphics.image.PDImageXObject;
import org.apache.pdfbox.cos.COSName;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * PDF Splitter utility for splitting large PDFs into smaller parts.
 * Each part is kept under the specified maximum size limit (default 10MB)
 * and maximum page count limit (default 49 pages).
 */
public class PdfSplitter {

    private static final Logger LOGGER = LoggerFactory.getLogger(PdfSplitter.class);

    // Default max size per part: 10 MB
    private static final long DEFAULT_MAX_PART_SIZE_BYTES = 10 * 1024 * 1024;

    // Default max pages per part: 49
    private static final int DEFAULT_MAX_PAGES_PER_PART = 49;

    // Maximum number of parts allowed
    private static final int MAX_PARTS = 5;

    /**
     * Analyzes a PDF to determine how it should be split.
     * Returns metadata about the PDF and proposed split plan.
     *
     * @param pdfBytes The PDF file as byte array
     * @param maxPartSizeBytes Maximum size per part in bytes
     * @return Map containing analysis results
     */
    public static Map<String, Object> analyzePdf(byte[] pdfBytes, Long maxPartSizeBytes) throws IOException {
        if (maxPartSizeBytes == null || maxPartSizeBytes <= 0) {
            maxPartSizeBytes = DEFAULT_MAX_PART_SIZE_BYTES;
        }

        Map<String, Object> result = new HashMap<>();

        PDDocument document = null;
        try {
            document = PDDocument.load(new ByteArrayInputStream(pdfBytes));
        } catch (IOException e) {
            // Enhanced error message with hex dump
            String errorMsg = "Failed to load PDF for analysis: " + e.getMessage();
            LOGGER.error("ANALYZE_ERROR | " + errorMsg);

            // Log first bytes for diagnostics
            if (pdfBytes != null && pdfBytes.length >= 8) {
                String hex = String.format("%02X %02X %02X %02X %02X %02X %02X %02X",
                    pdfBytes[0], pdfBytes[1], pdfBytes[2], pdfBytes[3],
                    pdfBytes[4], pdfBytes[5], pdfBytes[6], pdfBytes[7]);
                LOGGER.error("ANALYZE_ERROR | First 8 bytes (hex): {}", hex);
                LOGGER.error("ANALYZE_ERROR | Expected PDF magic bytes: 25 50 44 46 2D (%PDF-)");
            }

            throw new IOException(errorMsg + ". PDF may be corrupted, encrypted, or not a valid PDF file.", e);
        }

        try {
            int totalPages = document.getNumberOfPages();
            long totalSize = pdfBytes.length;

            result.put("totalPages", totalPages);
            result.put("totalSizeBytes", totalSize);

            // Estimate pages per part based on average page size
            long avgPageSize = totalSize / Math.max(totalPages, 1);
            int pagesPerPart = (int) Math.max(1, maxPartSizeBytes / Math.max(avgPageSize, 1));

            // Calculate number of parts needed
            int partCount = (int) Math.ceil((double) totalPages / pagesPerPart);

            // Ensure we don't exceed max parts
            if (partCount > MAX_PARTS) {
                pagesPerPart = (int) Math.ceil((double) totalPages / MAX_PARTS);
                partCount = MAX_PARTS;
            }

            result.put("estimatedPartCount", partCount);
            result.put("estimatedPagesPerPart", pagesPerPart);
            result.put("canSplit", true);

            // Build split plan
            List<Map<String, Object>> splitPlan = new ArrayList<>();
            int currentPage = 1;
            for (int i = 0; i < partCount; i++) {
                Map<String, Object> part = new HashMap<>();
                int pageStart = currentPage;
                int pageEnd = Math.min(currentPage + pagesPerPart - 1, totalPages);
                int pageCount = pageEnd - pageStart + 1;

                part.put("partNumber", i + 1);
                part.put("pageStart", pageStart);
                part.put("pageEnd", pageEnd);
                part.put("pageCount", pageCount);
                // Estimate size based on proportion of pages
                part.put("estimatedSizeBytes", (long) pageCount * avgPageSize);

                splitPlan.add(part);
                currentPage = pageEnd + 1;
            }

            result.put("splitPlan", splitPlan);

            LOGGER.info("PDF analysis complete: {} pages, {} bytes, {} estimated parts",
                    totalPages, totalSize, partCount);

            return result;
        } finally {
            if (document != null) {
                document.close();
            }
        }
    }

    /**
     * Helper class to represent a page range for splitting.
     */
    private static class PageRange {
        int start;  // 0-indexed
        int end;    // 0-indexed, inclusive
        long estimatedSize;

        PageRange(int start, int end, long estimatedSize) {
            this.start = start;
            this.end = end;
            this.estimatedSize = estimatedSize;
        }

        int getPageCount() {
            return end - start + 1;
        }
    }

    /**
     * Estimates the size overhead of a PDF document (headers, metadata, etc).
     * This is a rough estimate based on typical PDF structure.
     */
    private static long estimateDocumentOverhead(PDDocument doc) {
        // Typical overhead: PDF header (~200 bytes), catalog, metadata, xref table
        // For small docs: ~2KB, for larger docs with more objects: ~5-10KB
        int pageCount = doc.getNumberOfPages();
        long baseOverhead = 2000; // 2KB base
        long perPageOverhead = 50;  // ~50 bytes per page for xref entries
        return baseOverhead + (pageCount * perPageOverhead);
    }

    /**
     * Estimates the size of a single page without full serialization.
     * This is much faster than actually saving the document.
     *
     * @param page The PDF page to estimate
     * @return Estimated size in bytes
     */
    private static long estimatePageSize(PDPage page) {
        long estimatedSize = 0;

        try {
            // Estimate content stream size - use COSStream if available
            if (page.getContents() != null && page.getCOSObject() != null) {
                // Rough estimate: 10KB per page for content streams
                estimatedSize += 10240;
            }

            // Estimate resource sizes (images, fonts, etc.)
            PDResources resources = page.getResources();
            if (resources != null) {
                // Images often dominate page size
                for (COSName name : resources.getXObjectNames()) {
                    try {
                        PDXObject xobj = resources.getXObject(name);
                        if (xobj instanceof PDImageXObject) {
                            PDImageXObject image = (PDImageXObject) xobj;
                            // Estimate compressed image size
                            long imageSize = image.getCOSObject().getLength();
                            estimatedSize += imageSize;
                        }
                    } catch (Exception e) {
                        // Skip if unable to access resource
                        LOGGER.debug("Could not estimate resource size: {}", e.getMessage());
                    }
                }

                // Fonts (typically smaller than images) - count fonts
                int fontCount = 0;
                for (@SuppressWarnings("unused") COSName fontName : resources.getFontNames()) {
                    fontCount++;
                }
                estimatedSize += fontCount * 5000; // ~5KB per font (conservative)
            }

            // Add buffer for page dictionary, annotations, etc.
            estimatedSize += 500; // ~500 bytes overhead per page

        } catch (Exception e) {
            LOGGER.warn("Error estimating page size, using fallback: {}", e.getMessage());
            // Fallback: assume average of 100KB per page
            estimatedSize = 100 * 1024;
        }

        return Math.max(estimatedSize, 1024); // Minimum 1KB per page
    }

    /**
     * Pre-computes split boundaries based on estimated page sizes and max pages per part.
     * This avoids the need to serialize after each page addition.
     *
     * @param sourceDoc The source PDF document
     * @param maxPartSizeBytes Maximum size per part
     * @param maxPagesPerPart Maximum pages per part
     * @return List of page ranges for splitting
     */
    private static List<PageRange> computeSplitRanges(PDDocument sourceDoc, long maxPartSizeBytes, int maxPagesPerPart) {
        List<PageRange> ranges = new ArrayList<>();
        int totalPages = sourceDoc.getNumberOfPages();

        // Estimate overhead once
        long docOverhead = estimateDocumentOverhead(sourceDoc);
        LOGGER.info("Estimated document overhead: {} bytes", docOverhead);

        // Use 85% of limit to account for estimation error
        long targetSize = (long) (maxPartSizeBytes * 0.85);

        long currentSize = docOverhead;
        int rangeStart = 0;
        int currentPageCount = 0;

        for (int i = 0; i < totalPages; i++) {
            PDPage page = sourceDoc.getPage(i);
            long pageSize = estimatePageSize(page);

            LOGGER.debug("Page {}: estimated size = {} KB", i + 1, pageSize / 1024);

            // Check if adding this page would exceed the size target OR page limit
            boolean wouldExceedSize = currentSize + pageSize > targetSize && i > rangeStart;
            boolean wouldExceedPages = currentPageCount >= maxPagesPerPart;

            if (wouldExceedSize || wouldExceedPages) {
                // Save current range (up to previous page)
                ranges.add(new PageRange(rangeStart, i - 1, currentSize));
                LOGGER.info("Planned range: pages {}-{}, estimated {} KB, {} pages (reason: {})",
                        rangeStart + 1, i, currentSize / 1024, currentPageCount,
                        wouldExceedPages ? "page limit" : "size limit");

                // Start new range with current page
                rangeStart = i;
                currentSize = docOverhead + pageSize;
                currentPageCount = 1;
            } else {
                // Add page to current range
                currentSize += pageSize;
                currentPageCount++;
            }
        }

        // Add final range
        if (rangeStart < totalPages) {
            ranges.add(new PageRange(rangeStart, totalPages - 1, currentSize));
            LOGGER.info("Planned range: pages {}-{}, estimated {} KB, {} pages",
                    rangeStart + 1, totalPages, currentSize / 1024, totalPages - rangeStart);
        }

        return ranges;
    }

    /**
     * Creates a PDF document from a page range.
     */
    private static PDDocument createPartForRange(PDDocument sourceDoc, PageRange range) throws IOException {
        PDDocument part = new PDDocument();
        for (int i = range.start; i <= range.end; i++) {
            part.importPage(sourceDoc.getPage(i));
        }
        return part;
    }

    /**
     * Saves a PDDocument to a byte array.
     */
    private static byte[] saveToBytes(PDDocument doc) throws IOException {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        doc.save(baos);
        return baos.toByteArray();
    }

    /**
     * Splits a PDF into multiple parts based on the specified maximum part size
     * and maximum pages per part.
     * OPTIMIZED VERSION: Uses page size estimation to pre-compute split boundaries,
     * then creates only the final parts. This drastically reduces serialization operations.
     *
     * Fallback to incremental approach if estimation is significantly off.
     *
     * Constraints:
     * - Maximum 5 parts (MAX_PARTS)
     * - Each part strictly under maxPartSizeBytes (default 10MB)
     * - Each part has at most maxPagesPerPart pages (default 49)
     *
     * @param pdfBytes The PDF file as byte array
     * @param originalFileName Original file name (without extension)
     * @param maxPartSizeBytes Maximum size per part in bytes
     * @param maxPagesPerPart Maximum pages per part (null for default 49)
     * @return List of maps containing part info and byte arrays
     */
    public static List<Map<String, Object>> splitPdf(byte[] pdfBytes, String originalFileName, Long maxPartSizeBytes, Integer maxPagesPerPart) throws IOException {
        if (maxPartSizeBytes == null || maxPartSizeBytes <= 0) {
            maxPartSizeBytes = DEFAULT_MAX_PART_SIZE_BYTES;
        }
        if (maxPagesPerPart == null || maxPagesPerPart <= 0) {
            maxPagesPerPart = DEFAULT_MAX_PAGES_PER_PART;
        }

        // VERSION MARKER - confirms new code is running
        LOGGER.info("=== PdfSplitter v5.0 - SIZE + PAGE LIMIT SPLIT ===");

        LOGGER.info("Split config: sizeLimit={} MB, maxPagesPerPart={}",
                String.format("%.2f", maxPartSizeBytes / 1048576.0), maxPagesPerPart);

        List<Map<String, Object>> parts = new ArrayList<>();

        PDDocument sourceDoc = null;
        try {
            sourceDoc = PDDocument.load(new ByteArrayInputStream(pdfBytes));
        } catch (IOException e) {
            // Enhanced error message with hex dump
            String errorMsg = "Failed to load PDF for splitting: " + e.getMessage();
            LOGGER.error("SPLIT_ERROR | " + errorMsg);

            // Log first bytes for diagnostics
            if (pdfBytes != null && pdfBytes.length >= 8) {
                String hex = String.format("%02X %02X %02X %02X %02X %02X %02X %02X",
                    pdfBytes[0], pdfBytes[1], pdfBytes[2], pdfBytes[3],
                    pdfBytes[4], pdfBytes[5], pdfBytes[6], pdfBytes[7]);
                LOGGER.error("SPLIT_ERROR | First 8 bytes (hex): {}", hex);
                LOGGER.error("SPLIT_ERROR | Expected PDF magic bytes: 25 50 44 46 2D (%PDF-)");
            }

            throw new IOException(errorMsg + ". PDF may be corrupted, encrypted, or not a valid PDF file.", e);
        }

        try {
            int totalPages = sourceDoc.getNumberOfPages();
            long totalSize = pdfBytes.length;

            LOGGER.info("Source PDF: {} pages, {} MB", totalPages,
                    String.format("%.2f", totalSize / 1048576.0));

            // Early return for small files that are also within page limit
            if (totalSize <= maxPartSizeBytes && totalPages <= maxPagesPerPart) {
                LOGGER.info("PDF within size and page limits, returning as single part");
                parts.add(createSinglePart(pdfBytes, totalPages, originalFileName));
                return parts;
            }

            // Cannot split single-page PDF that exceeds size limit
            if (totalPages == 1 && totalSize > maxPartSizeBytes) {
                throw new IOException("Single-page PDF exceeds size limit: " +
                        String.format("%.2f", totalSize / 1048576.0) + " MB");
            }

            LOGGER.info("Split required: size={} MB (limit={} MB), pages={} (limit={})",
                    String.format("%.2f", totalSize / 1048576.0),
                    String.format("%.2f", maxPartSizeBytes / 1048576.0),
                    totalPages, maxPagesPerPart);

            // PHASE 1: Pre-compute split ranges based on estimation and page limit
            LOGGER.info("PHASE 1: Computing split ranges using page size estimation + page limit...");
            long estimationStart = System.currentTimeMillis();

            List<PageRange> ranges = computeSplitRanges(sourceDoc, maxPartSizeBytes, maxPagesPerPart);

            long estimationTime = System.currentTimeMillis() - estimationStart;
            LOGGER.info("Pre-computation complete in {} ms, {} ranges planned", estimationTime, ranges.size());

            // Validate estimated part count
            if (ranges.size() > MAX_PARTS) {
                throw new IOException("Cannot split into " + MAX_PARTS + " parts or fewer. " +
                        "Requires " + ranges.size() + " parts based on estimation.");
            }

            // PHASE 2: Create and serialize only the final parts
            LOGGER.info("PHASE 2: Creating final parts (only {} serializations)...", ranges.size());
            long serializationStart = System.currentTimeMillis();

            int partNumber = 1;
            List<Map<String, Object>> validatedParts = new ArrayList<>();

            for (PageRange range : ranges) {
                PDDocument part = null;
                try {
                    // Create part from range
                    part = createPartForRange(sourceDoc, range);

                    // Serialize once (not 500+ times!)
                    byte[] partBytes = saveToBytes(part);
                    long actualSize = partBytes.length;

                    LOGGER.info("Part {}: pages {}-{}, actual size = {} MB (estimated {} MB)",
                            partNumber,
                            range.start + 1,
                            range.end + 1,
                            String.format("%.2f", actualSize / 1048576.0),
                            String.format("%.2f", range.estimatedSize / 1048576.0));

                    // Check if actual size exceeds limit
                    if (actualSize > maxPartSizeBytes) {
                        LOGGER.warn("Part {} exceeds limit! Actual {} MB > {} MB. Estimation was off by {}%",
                                partNumber,
                                String.format("%.2f", actualSize / 1048576.0),
                                String.format("%.2f", maxPartSizeBytes / 1048576.0),
                                String.format("%.1f", ((actualSize - range.estimatedSize) * 100.0 / range.estimatedSize)));

                        // If estimation was significantly wrong, split this range further
                        if (range.getPageCount() > 1) {
                            LOGGER.info("Splitting range {}-{} into smaller chunks...",
                                    range.start + 1, range.end + 1);

                            List<Map<String, Object>> subParts = splitRangeIncremental(
                                    sourceDoc, range.start, range.end, maxPartSizeBytes,
                                    maxPagesPerPart, originalFileName, partNumber);

                            validatedParts.addAll(subParts);
                            partNumber += subParts.size();
                            continue;
                        } else {
                            // Single page exceeds limit
                            throw new IOException("Page " + (range.start + 1) + " alone exceeds limit: " +
                                    String.format("%.2f", actualSize / 1048576.0) + " MB");
                        }
                    }

                    // Size is good - add to parts
                    validatedParts.add(createPartMap(partNumber, range.start + 1, range.end + 1,
                            partBytes, originalFileName));
                    partNumber++;

                } finally {
                    if (part != null) {
                        part.close();
                    }
                }
            }

            parts = validatedParts;

            long serializationTime = System.currentTimeMillis() - serializationStart;
            LOGGER.info("Serialization complete in {} ms ({} operations vs {} incremental)",
                    serializationTime, ranges.size(), totalPages);

            // Final part count validation
            if (parts.size() > MAX_PARTS) {
                throw new IOException("Cannot split into " + MAX_PARTS + " parts or fewer. " +
                        "Requires " + parts.size() + " parts.");
            }
        } finally {
            if (sourceDoc != null) {
                sourceDoc.close();
            }
        }

        // ========== FINAL SAFEGUARD ==========
        // This is the LAST line of defense - verify EVERY part before returning
        LOGGER.info("=== FINAL SAFEGUARD: Checking {} parts (size <= {} MB, pages <= {})... ===",
                parts.size(), String.format("%.2f", maxPartSizeBytes / 1048576.0), maxPagesPerPart);
        for (Map<String, Object> part : parts) {
            byte[] partBytes = (byte[]) part.get("pdfBytes");
            long actualSize = partBytes.length;
            int partNum = (int) part.get("partNumber");
            int partPageCount = (int) part.get("pageCount");

            LOGGER.info("SAFEGUARD CHECK: Part {} size={} MB, pages={}",
                    partNum, String.format("%.2f", actualSize / 1048576.0), partPageCount);

            if (actualSize > maxPartSizeBytes) {
                LOGGER.error("!!! SAFEGUARD FAILED !!! Part {} = {} MB > {} MB size limit",
                        partNum,
                        String.format("%.2f", actualSize / 1048576.0),
                        String.format("%.2f", maxPartSizeBytes / 1048576.0));
                throw new IOException("SAFEGUARD FAILED: Part " + partNum +
                        " is " + String.format("%.2f", actualSize / 1048576.0) +
                        " MB, exceeds " + String.format("%.2f", maxPartSizeBytes / 1048576.0) + " MB size limit");
            }

            if (partPageCount > maxPagesPerPart) {
                LOGGER.error("!!! SAFEGUARD FAILED !!! Part {} has {} pages > {} page limit",
                        partNum, partPageCount, maxPagesPerPart);
                throw new IOException("SAFEGUARD FAILED: Part " + partNum +
                        " has " + partPageCount + " pages, exceeds " + maxPagesPerPart + " page limit");
            }

            LOGGER.info("SAFEGUARD PASSED: Part {} size={} MB, pages={}",
                    partNum, String.format("%.2f", actualSize / 1048576.0), partPageCount);
        }
        // ========== END SAFEGUARD ==========

        LOGGER.info("Split complete: {} parts, all VERIFIED (size <= {} MB, pages <= {})",
                parts.size(), String.format("%.2f", maxPartSizeBytes / 1048576.0), maxPagesPerPart);
        return parts;
    }

    /**
     * Splits a PDF file into multiple parts based on the specified maximum part size
     * and maximum pages per part.
     * OPTIMIZED VERSION for streaming: Accepts File instead of byte[] to reduce memory usage.
     *
     * @param pdfFile The PDF file to split
     * @param originalFileName Original file name (without extension)
     * @param maxPartSizeBytes Maximum size per part in bytes
     * @param maxPagesPerPart Maximum pages per part (null for default 49)
     * @return List of maps containing part info and byte arrays
     */
    public static List<Map<String, Object>> splitPdf(File pdfFile, String originalFileName, Long maxPartSizeBytes, Integer maxPagesPerPart) throws IOException {
        if (maxPartSizeBytes == null || maxPartSizeBytes <= 0) {
            maxPartSizeBytes = DEFAULT_MAX_PART_SIZE_BYTES;
        }
        if (maxPagesPerPart == null || maxPagesPerPart <= 0) {
            maxPagesPerPart = DEFAULT_MAX_PAGES_PER_PART;
        }

        LOGGER.info("=== PdfSplitter v5.0 - SIZE + PAGE LIMIT SPLIT (File-based) ===");
        LOGGER.info("Split config: sizeLimit={} MB, maxPagesPerPart={}, source file size={} MB",
                String.format("%.2f", maxPartSizeBytes / 1048576.0),
                maxPagesPerPart,
                String.format("%.2f", pdfFile.length() / 1048576.0));

        List<Map<String, Object>> parts = new ArrayList<>();

        PDDocument sourceDoc = null;
        try {
            sourceDoc = PDDocument.load(pdfFile);
        } catch (IOException e) {
            // Enhanced error message with hex dump
            String errorMsg = "Failed to load PDF file for splitting: " + e.getMessage();
            LOGGER.error("SPLIT_ERROR | " + errorMsg + " | file=" + pdfFile.getAbsolutePath());

            // Log first bytes for diagnostics
            try {
                byte[] firstBytes = new byte[8];
                java.io.FileInputStream fis = new java.io.FileInputStream(pdfFile);
                fis.read(firstBytes);
                fis.close();

                String hex = String.format("%02X %02X %02X %02X %02X %02X %02X %02X",
                    firstBytes[0], firstBytes[1], firstBytes[2], firstBytes[3],
                    firstBytes[4], firstBytes[5], firstBytes[6], firstBytes[7]);
                LOGGER.error("SPLIT_ERROR | First 8 bytes (hex): {}", hex);
                LOGGER.error("SPLIT_ERROR | Expected PDF magic bytes: 25 50 44 46 2D (%PDF-)");
            } catch (Exception readError) {
                LOGGER.error("SPLIT_ERROR | Could not read file bytes for diagnostics: {}", readError.getMessage());
            }

            throw new IOException(errorMsg + ". PDF may be corrupted, encrypted, or not a valid PDF file.", e);
        }

        try {
            int totalPages = sourceDoc.getNumberOfPages();
            long totalSize = pdfFile.length();

            LOGGER.info("Source PDF: {} pages, {} MB", totalPages,
                    String.format("%.2f", totalSize / 1048576.0));

            // Early return for small files that are also within page limit
            if (totalSize <= maxPartSizeBytes && totalPages <= maxPagesPerPart) {
                LOGGER.info("PDF within size and page limits, returning as single part");
                byte[] pdfBytes = Files.readAllBytes(pdfFile.toPath());
                parts.add(createSinglePart(pdfBytes, totalPages, originalFileName));
                return parts;
            }

            // Cannot split single-page PDF that exceeds size limit
            if (totalPages == 1 && totalSize > maxPartSizeBytes) {
                throw new IOException("Single-page PDF exceeds size limit: " +
                        String.format("%.2f", totalSize / 1048576.0) + " MB");
            }

            LOGGER.info("Split required: size={} MB (limit={} MB), pages={} (limit={})",
                    String.format("%.2f", totalSize / 1048576.0),
                    String.format("%.2f", maxPartSizeBytes / 1048576.0),
                    totalPages, maxPagesPerPart);

            // PHASE 1: Pre-compute split ranges
            LOGGER.info("PHASE 1: Computing split ranges using page size estimation + page limit...");
            long estimationStart = System.currentTimeMillis();

            List<PageRange> ranges = computeSplitRanges(sourceDoc, maxPartSizeBytes, maxPagesPerPart);

            long estimationTime = System.currentTimeMillis() - estimationStart;
            LOGGER.info("Pre-computation complete in {} ms, {} ranges planned", estimationTime, ranges.size());

            if (ranges.size() > MAX_PARTS) {
                throw new IOException("Cannot split into " + MAX_PARTS + " parts or fewer. " +
                        "Requires " + ranges.size() + " parts based on estimation.");
            }

            // PHASE 2: Create and serialize only the final parts
            LOGGER.info("PHASE 2: Creating final parts (only {} serializations)...", ranges.size());
            long serializationStart = System.currentTimeMillis();

            int partNumber = 1;
            List<Map<String, Object>> validatedParts = new ArrayList<>();

            for (PageRange range : ranges) {
                PDDocument part = null;
                try {
                    part = createPartForRange(sourceDoc, range);
                    byte[] partBytes = saveToBytes(part);
                    long actualSize = partBytes.length;

                    LOGGER.info("Part {}: pages {}-{}, actual size = {} MB (estimated {} MB)",
                            partNumber, range.start + 1, range.end + 1,
                            String.format("%.2f", actualSize / 1048576.0),
                            String.format("%.2f", range.estimatedSize / 1048576.0));

                    if (actualSize > maxPartSizeBytes) {
                        LOGGER.warn("Part {} exceeds limit! Using incremental fallback...", partNumber);

                        if (range.getPageCount() > 1) {
                            List<Map<String, Object>> subParts = splitRangeIncremental(
                                    sourceDoc, range.start, range.end, maxPartSizeBytes,
                                    maxPagesPerPart, originalFileName, partNumber);
                            validatedParts.addAll(subParts);
                            partNumber += subParts.size();
                            continue;
                        } else {
                            throw new IOException("Page " + (range.start + 1) + " alone exceeds limit");
                        }
                    }

                    validatedParts.add(createPartMap(partNumber, range.start + 1, range.end + 1,
                            partBytes, originalFileName));
                    partNumber++;

                } finally {
                    if (part != null) {
                        part.close();
                    }
                }
            }

            parts = validatedParts;

            long serializationTime = System.currentTimeMillis() - serializationStart;
            LOGGER.info("Serialization complete in {} ms", serializationTime);

            if (parts.size() > MAX_PARTS) {
                throw new IOException("Cannot split into " + MAX_PARTS + " parts or fewer. " +
                        "Requires " + parts.size() + " parts.");
            }
        } finally {
            if (sourceDoc != null) {
                sourceDoc.close();
            }
        }

        // FINAL SAFEGUARD
        LOGGER.info("=== FINAL SAFEGUARD: Checking {} parts (size <= {} MB, pages <= {})... ===",
                parts.size(), String.format("%.2f", maxPartSizeBytes / 1048576.0), maxPagesPerPart);
        for (Map<String, Object> part : parts) {
            byte[] partBytes = (byte[]) part.get("pdfBytes");
            long actualSize = partBytes.length;
            int partNum = (int) part.get("partNumber");
            int partPageCount = (int) part.get("pageCount");

            if (actualSize > maxPartSizeBytes) {
                throw new IOException("SAFEGUARD FAILED: Part " + partNum +
                        " is " + String.format("%.2f", actualSize / 1048576.0) +
                        " MB, exceeds " + String.format("%.2f", maxPartSizeBytes / 1048576.0) + " MB size limit");
            }
            if (partPageCount > maxPagesPerPart) {
                throw new IOException("SAFEGUARD FAILED: Part " + partNum +
                        " has " + partPageCount + " pages, exceeds " + maxPagesPerPart + " page limit");
            }
        }

        LOGGER.info("Split complete: {} parts, all VERIFIED (size <= {} MB, pages <= {})",
                parts.size(), String.format("%.2f", maxPartSizeBytes / 1048576.0), maxPagesPerPart);
        return parts;
    }

    /**
     * Fallback method: Incrementally build parts for a specific page range.
     * Used when pre-computation estimation is significantly off.
     *
     * @param sourceDoc Source PDF document
     * @param rangeStart Start page index (0-based)
     * @param rangeEnd End page index (0-based, inclusive)
     * @param maxPartSizeBytes Size limit per part
     * @param maxPagesPerPart Maximum pages per part
     * @param originalFileName Original file name
     * @param startPartNumber Starting part number
     * @return List of parts created from this range
     */
    private static List<Map<String, Object>> splitRangeIncremental(
            PDDocument sourceDoc, int rangeStart, int rangeEnd, long maxPartSizeBytes,
            int maxPagesPerPart, String originalFileName, int startPartNumber) throws IOException {

        LOGGER.info("Using incremental split for pages {}-{} (maxPages={})",
                rangeStart + 1, rangeEnd + 1, maxPagesPerPart);

        List<Map<String, Object>> parts = new ArrayList<>();
        final long effectiveMaxSize = (long) (maxPartSizeBytes * 0.90);

        int partNumber = startPartNumber;
        int partStartPage = rangeStart;
        PDDocument currentPart = new PDDocument();
        byte[] lastValidBytes = null;
        int lastValidPageCount = 0;

        try {
            for (int pageIndex = rangeStart; pageIndex <= rangeEnd; pageIndex++) {
                currentPart.importPage(sourceDoc.getPage(pageIndex));

                ByteArrayOutputStream baos = new ByteArrayOutputStream();
                currentPart.save(baos);
                byte[] currentBytes = baos.toByteArray();
                long currentSize = currentBytes.length;

                boolean isLastPageInRange = (pageIndex == rangeEnd);
                boolean exceedsSize = currentSize > effectiveMaxSize;
                boolean exceedsPages = currentPart.getNumberOfPages() > maxPagesPerPart;
                boolean exceedsLimit = exceedsSize || exceedsPages;

                if (exceedsLimit && currentPart.getNumberOfPages() > 1) {
                    // Save previous state
                    if (lastValidBytes == null) {
                        throw new IOException("No valid state for range starting at page " + (rangeStart + 1));
                    }

                    if (lastValidBytes.length > maxPartSizeBytes) {
                        throw new IOException("Part exceeds hard limit at page " + pageIndex);
                    }

                    parts.add(createPartMap(partNumber, partStartPage + 1,
                            partStartPage + lastValidPageCount, lastValidBytes, originalFileName));

                    LOGGER.info("INCREMENTAL: Saved part {}: pages {}-{}",
                            partNumber, partStartPage + 1, partStartPage + lastValidPageCount);

                    // Start new part
                    currentPart.close();
                    currentPart = new PDDocument();
                    currentPart.importPage(sourceDoc.getPage(pageIndex));

                    baos = new ByteArrayOutputStream();
                    currentPart.save(baos);
                    currentBytes = baos.toByteArray();
                    currentSize = currentBytes.length;

                    if (currentSize > maxPartSizeBytes) {
                        throw new IOException("Single page " + (pageIndex + 1) + " exceeds limit");
                    }

                    partNumber++;
                    partStartPage = pageIndex;
                    lastValidBytes = currentBytes;
                    lastValidPageCount = 1;

                } else if (exceedsLimit && currentPart.getNumberOfPages() == 1) {
                    throw new IOException("Single page " + (pageIndex + 1) + " exceeds limit");
                } else {
                    lastValidBytes = currentBytes;
                    lastValidPageCount = currentPart.getNumberOfPages();
                }

                // Handle last page in range
                if (isLastPageInRange && !exceedsLimit) {
                    if (lastValidBytes.length > maxPartSizeBytes) {
                        throw new IOException("Final part exceeds limit in range");
                    }

                    parts.add(createPartMap(partNumber, partStartPage + 1,
                            pageIndex + 1, lastValidBytes, originalFileName));

                    LOGGER.info("INCREMENTAL: Saved final part {}: pages {}-{}",
                            partNumber, partStartPage + 1, pageIndex + 1);
                }
            }
        } finally {
            currentPart.close();
        }

        return parts;
    }

    /**
     * Creates a part metadata map with page range.
     */
    private static Map<String, Object> createPartMap(int partNumber, int pageStart, int pageEnd,
                                                      byte[] pdfBytes, String originalFileName) {
        Map<String, Object> part = new HashMap<>();
        part.put("partNumber", partNumber);
        part.put("pageStart", pageStart);
        part.put("pageEnd", pageEnd);
        part.put("pageCount", pageEnd - pageStart + 1);
        part.put("sizeBytes", (long) pdfBytes.length);
        part.put("pdfBytes", pdfBytes);
        part.put("fileName", String.format("%s_part%02d.pdf", originalFileName, partNumber));
        return part;
    }

    /**
     * Creates a single part for files that don't need splitting.
     */
    private static Map<String, Object> createSinglePart(byte[] pdfBytes, int totalPages, String originalFileName) {
        Map<String, Object> part = new HashMap<>();
        part.put("partNumber", 1);
        part.put("pageStart", 1);
        part.put("pageEnd", totalPages);
        part.put("pageCount", totalPages);
        part.put("sizeBytes", (long) pdfBytes.length);
        part.put("pdfBytes", pdfBytes);
        part.put("fileName", originalFileName + "_part01.pdf");
        return part;
    }

    /**
     * Validates that a byte array is a valid PDF.
     *
     * @param pdfBytes The file bytes to validate
     * @return true if valid PDF, false otherwise
     */
    public static boolean isValidPdf(byte[] pdfBytes) {
        if (pdfBytes == null || pdfBytes.length < 5) {
            return false;
        }

        // Check PDF magic number: %PDF-
        return pdfBytes[0] == 0x25 && // %
               pdfBytes[1] == 0x50 && // P
               pdfBytes[2] == 0x44 && // D
               pdfBytes[3] == 0x46 && // F
               pdfBytes[4] == 0x2D;   // -
    }

    /**
     * Gets the page count of a PDF.
     *
     * @param pdfBytes The PDF file as byte array
     * @return Number of pages
     */
    public static int getPageCount(byte[] pdfBytes) throws IOException {
        PDDocument document = null;
        try {
            document = PDDocument.load(new ByteArrayInputStream(pdfBytes));
        } catch (IOException e) {
            // Enhanced error message with hex dump
            String errorMsg = "Failed to load PDF to get page count: " + e.getMessage();
            LOGGER.error("PAGECOUNT_ERROR | " + errorMsg);

            // Log first bytes for diagnostics
            if (pdfBytes != null && pdfBytes.length >= 8) {
                String hex = String.format("%02X %02X %02X %02X %02X %02X %02X %02X",
                    pdfBytes[0], pdfBytes[1], pdfBytes[2], pdfBytes[3],
                    pdfBytes[4], pdfBytes[5], pdfBytes[6], pdfBytes[7]);
                LOGGER.error("PAGECOUNT_ERROR | First 8 bytes (hex): {}", hex);
                LOGGER.error("PAGECOUNT_ERROR | Expected PDF magic bytes: 25 50 44 46 2D (%PDF-)");
            }

            throw new IOException(errorMsg + ". PDF may be corrupted, encrypted, or not a valid PDF file.", e);
        }

        try {
            return document.getNumberOfPages();
        } finally {
            if (document != null) {
                document.close();
            }
        }
    }
}