import http from 'http';
import { Server as SocketIOServer } from 'socket.io';
import { createApp } from './app';
import { config } from './config';
import { setupSocketHandlers } from './sockets/socketHandler';

const app = createApp();
const server = http.createServer(app);

// Setup Socket.IO for real-time signaling & presence
const io = new SocketIOServer(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
  pingInterval: 25000,
  pingTimeout: 20000,
});

setupSocketHandlers(io);

server.listen(config.port, () => {
  console.log(`=======================================================`);
  console.log(`⚡ VYBE VOICE SOCIAL BACKEND RUNNING ON PORT ${config.port}`);
  console.log(`⚡ API Prefix: http://localhost:${config.port}${config.apiPrefix}`);
  console.log(`⚡ Admin Dashboard: http://localhost:${config.port}/api/v1/admin/dashboard`);
  console.log(`⚡ Environment: ${config.nodeEnv}`);
  console.log(`=======================================================`);
});

export { server, io };
