import express, { Application } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { config } from './config';
import apiRoutes from './routes/apiRoutes';
import { errorHandler } from './middleware/errorHandler';

export function createApp(): Application {
  const app = express();

  // Security Middleware
  app.use(helmet({
    contentSecurityPolicy: false, // Allows admin dashboard CDN/styles
  }));

  // CORS
  app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-admin-secret'],
  }));

  // Request Logging
  if (config.nodeEnv !== 'test') {
    app.use(morgan('dev'));
  }

  // Body Parsing
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));

  // Root redirect to Admin Dashboard
  app.get('/', (req, res) => {
    res.redirect('/api/v1/admin/dashboard');
  });

  // Mount API v1 Routes
  app.use(config.apiPrefix, apiRoutes);

  // Global Error Handler
  app.use(errorHandler);

  return app;
}
