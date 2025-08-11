// Helfy task
// Matvey Guralskiy

document.getElementById('loginForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    const username = document.getElementById('username').value;
    const password = document.getElementById('password').value;

    try {
        const res = await fetch('http://localhost:3000/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password })
        });

        const data = await res.json();
        if (data.token) {
            localStorage.setItem('token', data.token);
            document.getElementById('result').innerText = `Login success! Welcome, ${data.username}! Token saved.`;
        } else {
            document.getElementById('result').innerText = 'Login failed';
        }
    } catch (err) {
        document.getElementById('result').innerText = 'Error connecting to server';
    }
});
