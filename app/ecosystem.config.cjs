module.exports = {
  apps: [
    {
      name: 'simulation-app',
      script: './server.js',
      exec_mode: 'cluster',
      instances: 2,
      autorestart: true,
      kill_timeout: 25_000,
      listen_timeout: 10_000,
      max_memory_restart: '850M',
      merge_logs: true
    };
  ]
};
