"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.io = exports.server = void 0;
const http_1 = __importDefault(require("http"));
const socket_io_1 = require("socket.io");
const app_1 = require("./app");
const config_1 = require("./config");
const socketHandler_1 = require("./sockets/socketHandler");
const supabaseClient_1 = require("./integrations/supabase/supabaseClient");
const app = (0, app_1.createApp)();
const server = http_1.default.createServer(app);
exports.server = server;
// Setup Socket.IO for real-time signaling & presence
const io = new socket_io_1.Server(server, {
    cors: {
        origin: '*',
        methods: ['GET', 'POST'],
    },
    pingInterval: 25000,
    pingTimeout: 20000,
});
exports.io = io;
(0, socketHandler_1.setupSocketHandlers)(io);
server.listen(config_1.config.port, async () => {
    const sbConnected = !!(0, supabaseClient_1.getSupabase)();
    console.log(`=======================================================`);
    console.log(`⚡ VYBE VOICE SOCIAL BACKEND RUNNING ON PORT ${config_1.config.port}`);
    console.log(`⚡ API Prefix: http://localhost:${config_1.config.port}${config_1.config.apiPrefix}`);
    console.log(`⚡ Admin Dashboard: http://localhost:${config_1.config.port}/api/v1/admin/dashboard`);
    console.log(`⚡ Environment: ${config_1.config.nodeEnv}`);
    console.log(`⚡ Supabase Live Integration: ${sbConnected ? 'CONNECTED' : 'STANDALONE (Fallback)'}`);
    console.log(`=======================================================`);
    if (sbConnected) {
        await (0, supabaseClient_1.syncUsersFromSupabase)();
    }
});
