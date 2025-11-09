import sharp = require('sharp');
import { AzureBlobClient, downloadBlob, uploadBlob } from './blob.service';

interface ImageEvent {
    imageId: string;
    mimeType: string;
    rawContainer: string;
    processedContainer: string;
}

export async function processImageWithWatermark(
    client: AzureBlobClient,
    event: ImageEvent
): Promise<void> {
    const { imageId, rawContainer, processedContainer } = event;

    console.log(`[Processor] Processing image: ${imageId}`);
    console.log(`[Processor] Raw container: ${rawContainer}`);
    console.log(`[Processor] Processed container: ${processedContainer}`);

    try {
        // Download blob from Azure Blob Storage
        const imageBuffer = await downloadBlob(client, rawContainer, imageId);
        console.log(`[Processor] Downloaded image: ${imageId}, size: ${imageBuffer.length} bytes`);

        // Process image with Sharp
        const watermarkedBuffer = await sharp(imageBuffer)
            .resize({ width: 800, withoutEnlargement: true })
            .composite([{
                input: Buffer.from(
                    '<svg><text x="50%" y="90%" font-size="20" fill="rgba(255,255,255,0.5)" text-anchor="middle">Recipe Manager</text></svg>'
                ),
                gravity: 'south',
            }])
            .toFormat('jpeg')
            .toBuffer();

        console.log(`[Processor] Watermarked image created, size: ${watermarkedBuffer.length} bytes`);

        // Upload processed blob back to Azure
        const processedBlobName = `watermarked-${imageId}.jpeg`;
        await uploadBlob(
            client,
            processedContainer,
            processedBlobName,
            watermarkedBuffer,
            'image/jpeg'
        );

        console.log(`[Processor] Successfully watermarked and uploaded: ${processedBlobName}`);
    } catch (error) {
        console.error(`[Processor] Failed to process image ${imageId}:`, error);
        throw error;
    }
}