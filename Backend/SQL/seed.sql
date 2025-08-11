INSERT INTO users (username, password) VALUES ('admin', 'adminpass') 
ON DUPLICATE KEY UPDATE username=username;
