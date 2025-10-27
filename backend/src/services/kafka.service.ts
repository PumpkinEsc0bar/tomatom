import { Kafka, Producer, Consumer } from 'kafkajs';
import { MinioClient } from './minio.service';
import { processImageWithWatermark } from './image.processor';

export type KafkaProducer = Producer;

export function initKafka(): KafkaProducer {
    const kafka = new Kafka({
        clientId: 'recipe-backend-api',
        brokers: (process.env.KAFKA_BROKERS || 'kafka:29092').split(','),
        retry: {
            initialRetryTime: 300,
            retries: 10,
            multiplier: 2,
            maxRetryTime: 30000
        }
    });
    const producer = kafka.producer();
    producer.connect();
    return producer;
}

export async function KafkaConsumer(brokers: string, topic: string, minioClient: MinioClient) {
    const kafka = new Kafka({
        clientId: 'image-processor-service',
        brokers: brokers.split(','),
    });

    const consumer: Consumer = kafka.consumer({ groupId: 'image-processor-group' });
    await consumer.connect();
    await consumer.subscribe({ topic, fromBeginning: true });

    await consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
            if (!message.value) return;

            try {
                const event = JSON.parse(message.value.toString());
                console.log(`[Kafka] Received event for image: ${event.imageId}`);

                await processImageWithWatermark(minioClient, event);

            } catch (error) {
                console.error(`[Kafka] Error processing message: ${error}`);
                // retry or DLT (Dead Letter Topic)
            }
        },
    });
}
