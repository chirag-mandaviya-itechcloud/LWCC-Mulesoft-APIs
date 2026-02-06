package com.lwcc.pdf;

import org.apache.pdfbox.cos.COSName;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDResources;
import org.apache.pdfbox.pdmodel.graphics.form.PDFormXObject;
import org.apache.pdfbox.pdmodel.graphics.image.JPEGFactory;
import org.apache.pdfbox.pdmodel.graphics.image.PDImageXObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.awt.image.RescaleOp;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;

/**
 * PDF Compressor utility for reducing PDF file sizes.
 * Optimized for Gemini AI document summarization.
 *
 * Gemini API Requirements:
 * - Images ≤384px = 258 tokens
 * - Larger images = 768×768 tiles (258 tokens each)
 * - Clear, non-blurry images for text recognition
 *
 * Features:
 * - Grayscale conversion for scanned documents
 * - High-quality rendering hints for downscaling
 * - Recursive processing of Form XObjects
 * - Contrast enhancement for better OCR
 * - Optimized for Gemini tile size (768px)
 */
public class PdfCompressor {

    private static final Logger LOGGER = LoggerFactory.getLogger(PdfCompressor.class);

    // Compression level constants
    public static final String LEVEL_NONE = "none";
    public static final String LEVEL_LOW = "low";
    public static final String LEVEL_MEDIUM = "medium";
    public static final String LEVEL_HIGH = "high";
    public static final String LEVEL_MAXIMUM = "maximum";

    // Default compression level
    private static final String DEFAULT_COMPRESSION_LEVEL = LEVEL_MEDIUM;

    // Minimum image size to compress (skip images smaller than this)
    private static final long MIN_IMAGE_SIZE_TO_COMPRESS = 30000; // 30KB

    // Compression settings per level
    private static final Map<String, CompressionSettings> COMPRESSION_PRESETS = new HashMap<>();

    static {
        // Optimized for Gemini API document summarization
        // 768px matches Gemini tile size for efficient token usage

        // none: No compression, return original
        COMPRESSION_PRESETS.put(LEVEL_NONE, new CompressionSettings(1.0f, 4000, false, false, false));
        // low: Light compression, preserve quality
        COMPRESSION_PRESETS.put(LEVEL_LOW, new CompressionSettings(0.65f, 1500, false, false, false));
        // medium: Balanced compression
        COMPRESSION_PRESETS.put(LEVEL_MEDIUM, new CompressionSettings(0.55f, 1200, true, false, false));
        // high: Good balance for Gemini (readable text, smaller size)
        COMPRESSION_PRESETS.put(LEVEL_HIGH, new CompressionSettings(0.45f, 1000, true, true, true));
        // maximum: Gemini-optimized (768px = 1 tile = 258 tokens)
        COMPRESSION_PRESETS.put(LEVEL_MAXIMUM, new CompressionSettings(0.35f, 768, true, true, true));
    }

    /**
     * Inner class to hold compression settings for each level.
     */
    private static class CompressionSettings {
        final float jpegQuality;
        final int maxImagePixels;
        final boolean removeMetadata;
        final boolean convertToGrayscale;
        final boolean enhanceContrast;

        CompressionSettings(float jpegQuality, int maxImagePixels, boolean removeMetadata,
                           boolean convertToGrayscale, boolean enhanceContrast) {
            this.jpegQuality = jpegQuality;
            this.maxImagePixels = maxImagePixels;
            this.removeMetadata = removeMetadata;
            this.convertToGrayscale = convertToGrayscale;
            this.enhanceContrast = enhanceContrast;
        }
    }

    /**
     * Compresses a PDF using the specified compression level.
     * Returns a Map containing compressed bytes and compression metrics.
     *
     * @param pdfBytes Original PDF as byte array
     * @param compressionLevel Compression level: "none", "low", "medium", "high", "maximum"
     * @return Map containing compression results and metrics
     * @throws IOException if PDF processing fails
     */
    public static Map<String, Object> compressPdf(byte[] pdfBytes, String compressionLevel) throws IOException {
        Map<String, Object> result = new HashMap<>();
        long originalSize = pdfBytes.length;
        result.put("originalSizeBytes", originalSize);

        // Validate and normalize compression level
        if (compressionLevel == null || compressionLevel.trim().isEmpty()) {
            compressionLevel = DEFAULT_COMPRESSION_LEVEL;
        }
        compressionLevel = compressionLevel.toLowerCase().trim();

        if (!COMPRESSION_PRESETS.containsKey(compressionLevel)) {
            LOGGER.warn("Invalid compression level '{}', using default '{}'",
                    compressionLevel, DEFAULT_COMPRESSION_LEVEL);
            compressionLevel = DEFAULT_COMPRESSION_LEVEL;
        }

        result.put("compressionLevel", compressionLevel);

        // If compression is disabled, return original
        if (LEVEL_NONE.equals(compressionLevel)) {
            LOGGER.info("COMPRESS | Compression disabled (level=none), returning original PDF");
            result.put("compressedBytes", pdfBytes);
            result.put("compressedSizeBytes", originalSize);
            result.put("compressionRatio", 1.0);
            result.put("savingsPercent", 0.0);
            result.put("wasCompressed", false);
            return result;
        }

        CompressionSettings settings = COMPRESSION_PRESETS.get(compressionLevel);

        LOGGER.info("COMPRESS_START | originalSize={} bytes ({} MB) | level={} | jpegQuality={}% | maxPixels={} | grayscale={}",
                originalSize, String.format("%.2f", originalSize / 1048576.0),
                compressionLevel, (int)(settings.jpegQuality * 100),
                settings.maxImagePixels, settings.convertToGrayscale);

        PDDocument document = null;
        try {
            document = PDDocument.load(new ByteArrayInputStream(pdfBytes));
        } catch (IOException e) {
            // Enhanced error message with hex dump
            String errorMsg = "Failed to load PDF for compression: " + e.getMessage();
            LOGGER.error("COMPRESS_ERROR | " + errorMsg);

            // Log first bytes for diagnostics
            if (pdfBytes != null && pdfBytes.length >= 8) {
                String hex = String.format("%02X %02X %02X %02X %02X %02X %02X %02X",
                    pdfBytes[0], pdfBytes[1], pdfBytes[2], pdfBytes[3],
                    pdfBytes[4], pdfBytes[5], pdfBytes[6], pdfBytes[7]);
                LOGGER.error("COMPRESS_ERROR | First 8 bytes (hex): {}", hex);
                LOGGER.error("COMPRESS_ERROR | Expected PDF magic bytes: 25 50 44 46 2D (%PDF-)");
            }

            throw new IOException(errorMsg + ". PDF may be corrupted, encrypted, or not a valid PDF file.", e);
        }

        try {
            int[] counts = {0, 0}; // [imageCount, compressedImageCount]

            // Process each page
            for (PDPage page : document.getPages()) {
                PDResources resources = page.getResources();
                if (resources != null) {
                    processResources(document, resources, settings, counts);
                }
            }

            // Remove metadata if configured
            if (settings.removeMetadata) {
                removeMetadata(document);
            }

            // Save compressed document
            ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
            document.save(outputStream);
            byte[] compressedBytes = outputStream.toByteArray();

            long compressedSize = compressedBytes.length;
            double compressionRatio = (double) compressedSize / originalSize;
            double savingsPercent = (1.0 - compressionRatio) * 100;

            LOGGER.info("COMPRESS_COMPLETE | originalSize={} ({} MB) | compressedSize={} ({} MB) | savings={}% | images={}/{}",
                    originalSize, String.format("%.2f", originalSize / 1048576.0),
                    compressedSize, String.format("%.2f", compressedSize / 1048576.0),
                    String.format("%.1f", savingsPercent),
                    counts[1], counts[0]);

            // Only use compressed version if it's actually smaller
            if (compressedSize < originalSize) {
                result.put("compressedBytes", compressedBytes);
                result.put("compressedSizeBytes", compressedSize);
                result.put("compressionRatio", compressionRatio);
                result.put("savingsPercent", savingsPercent);
                result.put("wasCompressed", true);
            } else {
                LOGGER.info("COMPRESS | Compressed size >= original, using original PDF");
                result.put("compressedBytes", pdfBytes);
                result.put("compressedSizeBytes", originalSize);
                result.put("compressionRatio", 1.0);
                result.put("savingsPercent", 0.0);
                result.put("wasCompressed", false);
            }

            result.put("imagesProcessed", counts[0]);
            result.put("imagesCompressed", counts[1]);

            return result;
        } finally {
            if (document != null) {
                document.close();
            }
        }
    }

    /**
     * Recursively processes resources including nested Form XObjects.
     */
    private static void processResources(PDDocument document, PDResources resources,
                                         CompressionSettings settings, int[] counts) {
        if (resources == null) {
            return;
        }

        for (COSName name : resources.getXObjectNames()) {
            try {
                // Process images
                if (resources.isImageXObject(name)) {
                    counts[0]++; // imageCount
                    PDImageXObject image = (PDImageXObject) resources.getXObject(name);

                    // Skip small images
                    long imageSize = image.getStream().getLength();
                    if (imageSize < MIN_IMAGE_SIZE_TO_COMPRESS) {
                        LOGGER.debug("COMPRESS | Skipping small image '{}' ({} bytes)", name.getName(), imageSize);
                        continue;
                    }

                    PDImageXObject compressedImage = compressImage(document, image, settings);

                    if (compressedImage != null && compressedImage != image) {
                        resources.put(name, compressedImage);
                        counts[1]++; // compressedImageCount
                    }
                }
                // Process nested Form XObjects (may contain images)
                else {
                    try {
                        Object xObject = resources.getXObject(name);
                        if (xObject instanceof PDFormXObject) {
                            PDFormXObject form = (PDFormXObject) xObject;
                            if (form.getResources() != null) {
                                LOGGER.debug("COMPRESS | Processing nested Form XObject '{}'", name.getName());
                                processResources(document, form.getResources(), settings, counts);
                            }
                        }
                    } catch (Exception ignored) {
                        // Not a Form XObject, skip
                    }
                }
            } catch (Exception e) {
                LOGGER.warn("COMPRESS | Failed to process XObject '{}': {}",
                        name.getName(), e.getMessage());
            }
        }
    }

    /**
     * Compresses a single image using the specified settings.
     * Includes grayscale conversion and high-quality downscaling.
     */
    private static PDImageXObject compressImage(PDDocument document, PDImageXObject image,
                                                CompressionSettings settings) throws IOException {
        BufferedImage bufferedImage = image.getImage();
        if (bufferedImage == null) {
            return image;
        }

        int width = bufferedImage.getWidth();
        int height = bufferedImage.getHeight();
        int maxPixels = settings.maxImagePixels;

        LOGGER.debug("COMPRESS_IMAGE | Processing {}x{} image", width, height);

        // Step 1: Convert to grayscale if enabled (major size reduction for scanned docs)
        if (settings.convertToGrayscale) {
            BufferedImage grayscale = new BufferedImage(width, height, BufferedImage.TYPE_BYTE_GRAY);
            Graphics2D g = grayscale.createGraphics();
            g.drawImage(bufferedImage, 0, 0, null);
            g.dispose();
            bufferedImage = grayscale;
            LOGGER.debug("COMPRESS_IMAGE | Converted to grayscale");
        }

        // Step 2: Enhance contrast for better text readability (Gemini OCR)
        if (settings.enhanceContrast) {
            // Increase contrast: scaleFactor=1.2 (20% more contrast), offset=10 (slight brightness)
            RescaleOp rescaleOp = new RescaleOp(1.2f, 10f, null);
            bufferedImage = rescaleOp.filter(bufferedImage, null);
            LOGGER.debug("COMPRESS_IMAGE | Enhanced contrast for OCR");
        }

        // Step 3: Downsample if needed
        boolean needsResize = (width > maxPixels || height > maxPixels);

        if (needsResize) {
            // Calculate new dimensions maintaining aspect ratio
            double scale = Math.min((double) maxPixels / width, (double) maxPixels / height);
            int newWidth = Math.max(1, (int) (width * scale));
            int newHeight = Math.max(1, (int) (height * scale));

            // Create resized image with high-quality rendering
            int imageType = settings.convertToGrayscale ? BufferedImage.TYPE_BYTE_GRAY : BufferedImage.TYPE_INT_RGB;
            BufferedImage resizedImage = new BufferedImage(newWidth, newHeight, imageType);
            Graphics2D g2d = resizedImage.createGraphics();

            // Apply high-quality rendering hints
            g2d.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
            g2d.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            g2d.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
            g2d.setRenderingHint(RenderingHints.KEY_COLOR_RENDERING, RenderingHints.VALUE_COLOR_RENDER_QUALITY);

            g2d.drawImage(bufferedImage, 0, 0, newWidth, newHeight, null);
            g2d.dispose();

            bufferedImage = resizedImage;

            LOGGER.debug("COMPRESS_IMAGE | Resized from {}x{} to {}x{}", width, height, newWidth, newHeight);
        }

        // Step 4: Re-encode as JPEG with specified quality
        return JPEGFactory.createFromImage(document, bufferedImage, settings.jpegQuality);
    }

    /**
     * Removes unnecessary metadata from the PDF document.
     */
    private static void removeMetadata(PDDocument document) {
        // Clear document information
        document.getDocumentInformation().setAuthor(null);
        document.getDocumentInformation().setCreator(null);
        document.getDocumentInformation().setProducer(null);
        document.getDocumentInformation().setSubject(null);
        document.getDocumentInformation().setKeywords(null);
        document.getDocumentInformation().setTitle(null);

        // Clear XMP metadata
        document.getDocumentCatalog().setMetadata(null);

        LOGGER.debug("COMPRESS | Removed document metadata");
    }

    /**
     * Simple compression method using default settings.
     *
     * @param pdfBytes Original PDF bytes
     * @return Compressed PDF bytes
     */
    public static byte[] compress(byte[] pdfBytes) throws IOException {
        Map<String, Object> result = compressPdf(pdfBytes, DEFAULT_COMPRESSION_LEVEL);
        return (byte[]) result.get("compressedBytes");
    }

    /**
     * Validates compression level string.
     *
     * @param level The compression level to validate
     * @return true if valid, false otherwise
     */
    public static boolean isValidCompressionLevel(String level) {
        if (level == null) {
            return false;
        }
        return COMPRESSION_PRESETS.containsKey(level.toLowerCase().trim());
    }

    /**
     * Returns available compression levels.
     *
     * @return Array of valid compression level names
     */
    public static String[] getAvailableCompressionLevels() {
        return new String[]{LEVEL_NONE, LEVEL_LOW, LEVEL_MEDIUM, LEVEL_HIGH, LEVEL_MAXIMUM};
    }
}
