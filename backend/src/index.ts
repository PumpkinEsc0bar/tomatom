import express, { Request, Response } from 'express';
import multer from 'multer';
import { AzureBlobClient, initAzureBlob, ensureContainers, uploadBlob } from './services/blob.service';
import { EventHubProducer, initEventHubProducer, initEventHubConsumer } from './services/eventhub.service';
import * as dotenv from 'dotenv';

dotenv.config();

const app = express();
const upload = multer({ storage: multer.memoryStorage() });

const PORT = process.env.PORT || 8080;
const TOPIC = process.env.KAFKA_TOPIC || 'image-uploads';
const RAW_CONTAINER = process.env.RAW_CONTAINER_NAME || 'recipe-raw-images';
const PROCESSED_CONTAINER = process.env.PROCESSED_CONTAINER_NAME || 'recipe-processed-images';

let blobClient: AzureBlobClient;
let eventHubProducer: EventHubProducer;

async function initializeServices() {
    console.log('[Init] Starting service initialization...');

    // Initialize Azure Blob Storage
    blobClient = initAzureBlob();

    // Initialize Event Hub Producer
    eventHubProducer = initEventHubProducer();

    try {
        // Ensure containers exist
        await ensureContainers(blobClient, RAW_CONTAINER, PROCESSED_CONTAINER);
        console.log('[Init] Azure Blob Storage containers ready.');
    } catch (error) {
        console.error('[Init] Fatal: Failed to initialize Azure Blob Storage containers.', error);
        process.exit(1);
    }

    // Start Event Hub Consumer
    try {
        await initEventHubConsumer(TOPIC, blobClient);
        console.log('[Init] Event Hub consumer started successfully.');
    } catch (error) {
        console.error('[Init] Warning: Event Hub consumer failed to start:', error);
        // Don't exit - producer can still work
    }

    console.log('[Init] All services initialized successfully.');
}

// --- CORS Middleware (if needed) ---
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    if (req.method === 'OPTIONS') {
        return res.sendStatus(200);
    }
    next();
});

app.use(express.json());

// --- Health Check Endpoint ---
app.get('/health', (req: Request, res: Response) => {
    res.status(200).json({
        status: 'healthy',
        timestamp: new Date().toISOString()
    });
});

// --- Upload API Endpoint ---
app.post('/api/upload', upload.single('image'), async (req: Request, res: Response) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded.' });
    }

    try {
        const file = req.file;
        const cleanFileName = file.originalname.replace(/\s/g, '-');
        const imageId = `${Date.now()}-${cleanFileName}`;

        console.log(`[API] Uploading raw image: ${imageId}`);

        // Upload to Azure Blob Storage
        await uploadBlob(
            blobClient,
            RAW_CONTAINER,
            imageId,
            file.buffer,
            file.mimetype
        );

        console.log(`[API] Raw image uploaded: ${imageId}`);

        // Send event to Event Hub
        const event = JSON.stringify({
            imageId,
            mimeType: file.mimetype,
            rawContainer: RAW_CONTAINER,
            processedContainer: PROCESSED_CONTAINER,
            timestamp: new Date().toISOString()
        });

        await eventHubProducer.send({
            topic: TOPIC,
            messages: [{
                key: imageId,
                value: event
            }],
        });

        console.log(`[API] Event sent to Event Hub for image: ${imageId}`);

        res.status(202).json({
            message: 'Image received, processing started.',
            id: imageId,
            rawContainer: RAW_CONTAINER,
            processedContainer: PROCESSED_CONTAINER
        });

    } catch (error) {
        console.error('[API] Upload Error:', error);
        res.status(500).json({
            error: 'Failed to process upload.',
            details: error instanceof Error ? error.message : 'Unknown error'
        });
    }
});

app.get('/api/images/latest', async (req: Request, res: Response) => {
    try {
        const containerClient = blobClient.getContainerClient(PROCESSED_CONTAINER);
        const blobs: { name: string; lastModified: Date }[] = [];

        for await (const blob of containerClient.listBlobsFlat()) {
            blobs.push({
                name: blob.name,
                lastModified: blob.properties.lastModified!
            });
        }

        blobs.sort((a, b) => b.lastModified.getTime() - a.lastModified.getTime());

        const latest10 = blobs.slice(0, 10).map(b => ({
            name: b.name,
            url: `${containerClient.url}/${b.name}`,
            lastModified: b.lastModified
        }));

        res.json(latest10);
    } catch (error) {
        console.error('[API] Failed to fetch latest images:', error);
        res.status(500).json({ error: 'Failed to fetch latest images.' });
    }
});

// --- Graceful Shutdown ---
process.on('SIGTERM', async () => {
    console.log('[Shutdown] SIGTERM received, closing connections...');
    try {
        await eventHubProducer.disconnect();
        console.log('[Shutdown] Event Hub producer disconnected.');
    } catch (error) {
        console.error('[Shutdown] Error during shutdown:', error);
    }
    process.exit(0);
});

// --- Start Server ---
initializeServices()
    .then(() => {
        app.listen(PORT, () => {
            console.log(`[Server] Running on port ${PORT}`);
            console.log(`[Server] Environment: ${process.env.NODE_ENV || 'development'}`);
            console.log(`[Server] Raw Container: ${RAW_CONTAINER}`);
            console.log(`[Server] Processed Container: ${PROCESSED_CONTAINER}`);
            console.log(`[Server] Event Hub Topic: ${TOPIC}`);
        });
    })
    .catch(err => {
        console.error('[Fatal] Initialization error:', err);
        process.exit(1);
    });