module.exports = {
  apps: [
    {
      name: 'airmoney',
      script: 'app.js',
      cwd: '/www/airmoney/server',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '512M',
      env: {
        NODE_ENV: 'production',
        PORT: 9002,
      },
    },
  ],
};