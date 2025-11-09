import { BlobServiceClient, ContainerClient } from '@azure/storage-blob';

export type AzureBlobClient = BlobServiceClient;

export function initAzureBlob(): AzureBlobClient {
    const connectionString = process.env.AZURE_STORAGE_CONNECTION_STRING;

    if (!connectionString) {
        throw new Error('AZURE_STORAGE_CONNECTION_STRING environment variable is required');
    }

    const blobServiceClient = BlobServiceClient.fromConnectionString(connectionString);
    console.log('[Azure Blob] Client initialized successfully');

    return blobServiceClient;
}

export async function ensureContainers(
    client: AzureBlobClient,
    rawContainer: string,
    processedContainer: string
): Promise<void> {
    const containers = [rawContainer, processedContainer];

    for (const containerName of containers) {
        try {
            const containerClient = client.getContainerClient(containerName);
            const exists = await containerClient.exists();

            if (!exists) {
                await containerClient.create({
                    access: 'blob' // Public read access for blobs
                });
                console.log(`[Azure Blob] Container '${containerName}' created successfully.`);
            } else {
                console.log(`[Azure Blob] Container '${containerName}' already exists.`);
            }
        } catch (error) {
            console.error(`[Azure Blob] Failed to create container ${containerName}:`, error);
            throw error;
        }
    }
}

export async function uploadBlob(
    client: AzureBlobClient,
    containerName: string,
    blobName: string,
    data: Buffer,
    contentType: string
): Promise<void> {
    const containerClient = client.getContainerClient(containerName);
    const blockBlobClient = containerClient.getBlockBlobClient(blobName);

    await blockBlobClient.uploadData(data, {
        blobHTTPHeaders: {
            blobContentType: contentType
        }
    });

    console.log(`[Azure Blob] Uploaded blob: ${blobName} to container: ${containerName}`);
}

export async function downloadBlob(
    client: AzureBlobClient,
    containerName: string,
    blobName: string
): Promise<Buffer> {
    const containerClient = client.getContainerClient(containerName);
    const blobClient = containerClient.getBlobClient(blobName);

    const downloadResponse = await blobClient.download(0);

    if (!downloadResponse.readableStreamBody) {
        throw new Error(`Failed to download blob: ${blobName}`);
    }

    const chunks: Buffer[] = [];
    for await (const chunk of downloadResponse.readableStreamBody) {
        chunks.push(Buffer.from(chunk));
    }

    const buffer = Buffer.concat(chunks);
    console.log(`[Azure Blob] Downloaded blob: ${blobName} from container: ${containerName}`);

    return buffer;
}

export function getBlobUrl(
    client: AzureBlobClient,
    containerName: string,
    blobName: string
): string {
    const containerClient = client.getContainerClient(containerName);
    const blobClient = containerClient.getBlobClient(blobName);
    return blobClient.url;
}