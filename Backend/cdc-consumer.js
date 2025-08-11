// Helfy task
// Matvey Guralskiy

require('dotenv').config();
const { Kafka } = require('kafkajs');

const kafka = new Kafka({
    clientId: 'cdc-consumer',
    brokers: [process.env.KAFKA_BROKER || 'kafka:9092'],
});

const consumer = kafka.consumer({ groupId: 'cdc-group' });

async function run() {
    await consumer.connect();
    await consumer.subscribe({ topic: 'ticdc-testdb-users', fromBeginning: true });

    await consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
            console.log({
                timestamp: new Date().toISOString(),
                topic,
                partition,
                key: message.key?.toString(),
                value: message.value?.toString(),
            });
        },
    });
}

run().catch(console.error);
