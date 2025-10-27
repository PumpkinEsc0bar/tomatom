import { Client } from 'minio';

export type MinioClient = Client;

export function initMinio(): MinioClient {
    // '!' - Docker Compose ГАРАНТУЄ,
    const endPoint = process.env.MINIO_ENDPOINT!;
    const port = parseInt(process.env.MINIO_PORT || '9000');

    if (!endPoint || isNaN(port) || !process.env.MINIO_ROOT_USER || !process.env.MINIO_ROOT_PASSWORD) {
        throw new Error('MinIO configuration environment variables are missing (MINIO_ENDPOINT, PORT, USER, or PASSWORD).');
    }

    const minioClient = new Client({
        endPoint: endPoint,
        port: port,
        useSSL: process.env.MINIO_USE_SSL === 'true',
        accessKey: process.env.MINIO_ROOT_USER!,
        secretKey: process.env.MINIO_ROOT_PASSWORD!
    });

    console.log(`[MinIO] Client initialized for: ${endPoint}:${port}`);
    return minioClient;
}

export async function makeBuckets(
    client: MinioClient,
    rawBucket: string,
    processedBucket: string
): Promise<void> {
    const buckets = [rawBucket, processedBucket];

    for (const bucketName of buckets) {
        try {
            const exists = await client.bucketExists(bucketName);
            if (!exists) {
                await client.makeBucket(bucketName, 'us-east-1');
                console.log(`[MinIO] Bucket '${bucketName}' created successfully.`);
            } else {
                console.log(`[MinIO] Bucket '${bucketName}' already exists.`);
            }
        } catch (error) {
            console.error(`[MinIO] Failed to create bucket ${bucketName}:`, error);
            throw error;
        }
    }
}