import sharp = require('sharp');
import { MinioClient } from './minio.service';

interface ImageEvent {
    imageId: string;
    mimeType: string;
    rawBucket: string;
    processedBucket: string;
}

export async function processImageWithWatermark(client: MinioClient, event: ImageEvent) {
    const { imageId, rawBucket, processedBucket } = event;
    const objectName = imageId;

    console.log(`event ${imageId}\n${rawBucket}\n${processedBucket}`);

    try {
        // download MinIO
        const stream = await client.getObject(rawBucket, objectName);
        const imageBuffer = await streamToBuffer(stream);

        // sharp
        const watermarkedBuffer = await sharp(imageBuffer)
            .resize({ width: 800, withoutEnlargement: true })
            .composite([{ // watermark
                input: Buffer.from('<svg><text x="50%" y="90%" font-size="20" fill="rgba(255,255,255,0.5)" text-anchor="middle">Recipe Manager</text></svg>'),
                gravity: 'south',
            }])
            .toFormat('jpeg')
            .toBuffer();

        // upload MinIO
        const processedObjectName = `watermarked-${objectName}.jpeg`;
        await client.putObject(processedBucket, processedObjectName, watermarkedBuffer, watermarkedBuffer.length, {
            'Content-Type': 'image/jpeg'
        });

        console.log(`[Processor] Successfully watermarked and uploaded: ${processedObjectName}`);

    } catch (error) {
        console.error(`[Processor] Failed to process image ${imageId}:`, error);
        throw error;
    }
}

function streamToBuffer(stream: NodeJS.ReadableStream): Promise<Buffer> {
    return new Promise((resolve, reject) => {
        const chunks: any[] = [];
        stream.on('data', chunk => chunks.push(chunk));
        stream.on('error', reject);
        stream.on('end', () => resolve(Buffer.concat(chunks)));
    });
}
