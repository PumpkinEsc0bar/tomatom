import express, { Request, Response } from 'express';
import multer from 'multer';
import { MinioClient, initMinio, makeBuckets } from './services/minio.service';
import { KafkaProducer, KafkaConsumer, initKafka } from './services/kafka.service';
import { processImageWithWatermark } from './services/image.processor';
import * as dotenv from 'dotenv';

dotenv.config();

const app = express();
const upload = multer({ storage: multer.memoryStorage() });

const PORT = process.env.PORT || 8080;
const TOPIC = process.env.KAFKA_TOPIC || 'image-uploads';
const RAW_BUCKET = process.env.RAW_BUCKET || 'recipe-raw-images';
const PROCESSED_BUCKET = process.env.PROCESSED_BUCKET || 'recipe-processed-images';

let minioClient: MinioClient;
let kafkaProducer: KafkaProducer;

async function initializeServices() {
    minioClient = initMinio();
    kafkaProducer = initKafka();
    try {
        await makeBuckets(minioClient, RAW_BUCKET, PROCESSED_BUCKET);
        console.log('[Init] MinIO buckets check complete.');
    } catch (error) {
        console.error('[Init] Fatal: Failed MinIO bucket initialization.', error);
        process.exit(1);
    }
    const KAFKA_BROKERS = process.env.KAFKA_BROKERS || 'kafka:29092';

    KafkaConsumer(KAFKA_BROKERS, TOPIC, minioClient);
    
    console.log('Services initialized: MinIO, Kafka Consumer started.');
}

// --- API ENDPOINT ---
app.post('/api/upload', upload.single('image'), async (req: Request, res: Response) => {
    if (!req.file) {
        return res.status(400).send('No file uploaded.');
    }

    try {
        const file = req.file;
        const cleanFileName = file.originalname.replace(/\s/g, '-');
        const imageId = `${Date.now()}-${cleanFileName}`;
        
        await minioClient.putObject(RAW_BUCKET, imageId, file.buffer, file.size, {
            'Content-Type': file.mimetype
        });
        console.log(`[API] Raw image uploaded: ${imageId}`);

        // send to Kafka
        const event = JSON.stringify({
            imageId,
            mimeType: file.mimetype,
            rawBucket: RAW_BUCKET,
            processedBucket: PROCESSED_BUCKET
        });

        await kafkaProducer.send({
            topic: TOPIC,
            messages: [{ key: imageId, value: event }],
        });
        console.log(`[API] Event sent to Kafka for image: ${imageId}`);

        res.status(202).send({
            message: 'Image received, processing started.',
            id: imageId
        });

    } catch (error) {
        console.error('Upload Error:', error);
        res.status(500).send('Failed to process upload.');
    }
});

// --- START ---
initializeServices().then(() => {
    app.listen(PORT, () => {
        console.log(`Server running on port ${PORT}`);
    });
}).catch(err => {
    console.error('Fatal initialization error:', err);
    process.exit(1);
});
