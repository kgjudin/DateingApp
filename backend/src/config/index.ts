import dotenv from 'dotenv';
dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || '5000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  apiPrefix: process.env.API_PREFIX || '/api/v1',
  corsOrigin: process.env.CORS_ORIGIN || '*',
  
  supabase: {
    url: process.env.SUPABASE_URL || 'https://dummy-vybe-project.supabase.co',
    anonKey: process.env.SUPABASE_ANON_KEY || 'dummy-anon-key',
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY || 'dummy-service-role-key',
    jwtSecret: process.env.JWT_SECRET || 'super-secret-vybe-jwt-key-change-in-production',
  },

  agora: {
    appId: process.env.AGORA_APP_ID || 'test_agora_app_id_vybe',
    appCertificate: process.env.AGORA_APP_CERTIFICATE || 'test_agora_cert_vybe',
    tokenExpiration: parseInt(process.env.AGORA_TOKEN_EXPIRATION_SECONDS || '86400', 10),
  },

  admin: {
    secretKey: process.env.ADMIN_SECRET_KEY || 'vybe-superadmin-secure-passcode',
  }
};
