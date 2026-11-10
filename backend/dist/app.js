"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createApp = createApp;
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const helmet_1 = __importDefault(require("helmet"));
const morgan_1 = __importDefault(require("morgan"));
const config_1 = require("./config");
const apiRoutes_1 = __importDefault(require("./routes/apiRoutes"));
const errorHandler_1 = require("./middleware/errorHandler");
function createApp() {
    const app = (0, express_1.default)();
    // Security Middleware
    app.use((0, helmet_1.default)({
        contentSecurityPolicy: false, // Allows admin dashboard CDN/styles
    }));
    // CORS
    app.use((0, cors_1.default)({
        origin: '*',
        methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
        allowedHeaders: ['Content-Type', 'Authorization', 'x-admin-secret'],
    }));
    // Request Logging
    if (config_1.config.nodeEnv !== 'test') {
        app.use((0, morgan_1.default)('dev'));
    }
    // Body Parsing
    app.use(express_1.default.json({ limit: '10mb' }));
    app.use(express_1.default.urlencoded({ extended: true, limit: '10mb' }));
    // Root redirect to Admin Dashboard
    app.get('/', (req, res) => {
        res.redirect('/api/v1/admin/dashboard');
    });
    // Mount API v1 Routes
    app.use(config_1.config.apiPrefix, apiRoutes_1.default);
    // Global Error Handler
    app.use(errorHandler_1.errorHandler);
    return app;
}
