import { Kafka, Producer, Consumer, logLevel } from 'kafkajs';
import { AzureBlobClient } from './blob.service';
import { processImageWithWatermark } from './image.processor';

export type EventHubProducer = Producer;

export function initEventHubProducer(): EventHubProducer {
    const namespace = process.env.EVENTHUB_NAMESPACE;
    const connectionString = process.env.EVENTHUB_CONNECTION_STRING;

    if (!namespace || !connectionString) {
        throw new Error('Event Hub configuration missing (EVENTHUB_NAMESPACE or EVENTHUB_CONNECTION_STRING)');
    }

    const kafka = new Kafka({
        clientId: 'recipe-backend-api',
        brokers: [`${namespace}.servicebus.windows.net:9093`],
        ssl: true,
        sasl: {
            mechanism: 'plain',
            username: '$ConnectionString',
            password: connectionString,
        },
        logLevel: logLevel.ERROR,
        retry: {
            initialRetryTime: 300,
            retries: 10,
            multiplier: 2,
            maxRetryTime: 30000
        },
        connectionTimeout: 30000,
        requestTimeout: 30000,
    });

    const producer = kafka.producer();

    producer.connect()
        .then(() => console.log('[Event Hub] Producer connected successfully'))
        .catch((error) => console.error('[Event Hub] Producer connection failed:', error));

    return producer;
}

export async function initEventHubConsumer(
    topic: string,
    blobClient: AzureBlobClient
): Promise<void> {
    const namespace = process.env.EVENTHUB_NAMESPACE;
    const connectionString = process.env.EVENTHUB_CONNECTION_STRING;

    if (!namespace || !connectionString) {
        throw new Error('Event Hub configuration missing for consumer');
    }

    const kafka = new Kafka({
        clientId: 'image-processor-service',
        brokers: [`${namespace}.servicebus.windows.net:9093`],
        ssl: true,
        sasl: {
            mechanism: 'plain',
            username: '$ConnectionString',
            password: connectionString,
        },
        logLevel: logLevel.ERROR,
        connectionTimeout: 30000,
        requestTimeout: 30000,
    });

    const consumer: Consumer = kafka.consumer({
        groupId: 'image-processor-group',
        sessionTimeout: 30000,
        heartbeatInterval: 3000,
    });

    await consumer.connect();
    console.log('[Event Hub] Consumer connected successfully');

    await consumer.subscribe({ topic, fromBeginning: true });
    console.log(`[Event Hub] Subscribed to topic: ${topic}`);

    await consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
            if (!message.value) return;

            try {
                const event = JSON.parse(message.value.toString());
                console.log(`[Event Hub] Received event for image: ${event.imageId}`);

                await processImageWithWatermark(blobClient, event);

                console.log(`[Event Hub] Successfully processed image: ${event.imageId}`);
            } catch (error) {
                console.error(`[Event Hub] Error processing message:`, error);
                // In production, implement retry logic or dead letter queue
            }
        },
    });
}