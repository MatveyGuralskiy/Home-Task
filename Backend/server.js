// Helfy task
// Matvey Guralskiy

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const mysql = require('mysql2/promise');
const { v4: uuidv4 } = require('uuid');
const log4js = require('log4js');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(express.json());

app.use(cors({
    origin: 'http://localhost:8080',
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'x-auth-token'],
}));

log4js.configure({
    appenders: {
        out: { type: 'stdout', layout: { type: 'pattern', pattern: '%d %p %c %m%n' } }
    },
    categories: {
        default: { appenders: ['out'], level: 'info' }
    }
});
const logger = log4js.getLogger();

const dbConfigWithoutDB = {
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
};

const dbConfig = {
    ...dbConfigWithoutDB,
    database: process.env.DB_NAME,
};

async function waitForDB(retries = 10, delay = 3000) {
    for (let i = 0; i < retries; i++) {
        try {
            const connection = await mysql.createConnection(dbConfigWithoutDB);
            await connection.end();
            console.log('DB is ready');
            return;
        } catch (e) {
            console.log(`Waiting for DB... retry ${i + 1}/${retries}`);
            await new Promise(r => setTimeout(r, delay));
        }
    }
    throw new Error('DB not ready after retries');
}

async function initDB() {
    const schema = fs.readFileSync(path.join(__dirname, 'SQL', 'schema.sql'), 'utf8');
    const seed = fs.readFileSync(path.join(__dirname, 'SQL', 'seed.sql'), 'utf8');

    const connection = await mysql.createConnection(dbConfigWithoutDB);

    await connection.query(`CREATE DATABASE IF NOT EXISTS \`${process.env.DB_NAME}\``);
    await connection.changeUser({ database: process.env.DB_NAME });

    await connection.query(schema);
    await connection.query(seed);

    await connection.end();

    console.log('Database initialized');
}

async function query(sql, params = []) {
    const conn = await mysql.createConnection(dbConfig);
    const [rows] = await conn.execute(sql, params);
    await conn.end();
    return rows;
}

app.post('/login', async (req, res) => {
    const { username, password } = req.body;
    if (!username || !password) return res.status(400).json({ error: 'Username and password required' });

    try {
        const users = await query('SELECT * FROM users WHERE username = ? AND password = ?', [username, password]);
        if (users.length === 0) return res.status(401).json({ error: 'Invalid credentials' });

        const token = uuidv4();
        await query('UPDATE users SET token = ? WHERE id = ?', [token, users[0].id]);

        logger.info({
            timestamp: new Date().toISOString(),
            userId: users[0].id,
            username,
            action: 'login',
            ip: req.ip
        });

        res.json({ token, username: users[0].username });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.get('/protected', async (req, res) => {
    const token = req.headers['x-auth-token'];
    if (!token) return res.status(401).json({ error: 'No token provided' });

    try {
        const users = await query('SELECT * FROM users WHERE token = ?', [token]);
        if (users.length === 0) return res.status(403).json({ error: 'Invalid token' });

        res.json({ message: `Welcome, ${users[0].username}!` });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

const PORT = process.env.PORT || 3000;

(async () => {
    try {
        await waitForDB();
        await initDB();
        app.listen(PORT, () => {
            console.log(`Server running on http://localhost:${PORT}`);
        });
    } catch (e) {
        console.error('DB init error:', e);
        process.exit(1);
    }
})();
