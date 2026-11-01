import dotenv from 'dotenv';
dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || '5000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  apiPrefix: process.env.API_PREFIX || '/api/v1',
  corsOrigin: process.env.CORS_ORIGIN || '*',
  
  supabase: {
    url: process.env.SUPABASE_URL || 'https://qkznhqzlaqnhesnmlmzb.supabase.co',
    anonKey: process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFrem5ocXpsYXFuaGVzbm1sbXpiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMzNzE5NTksImV4cCI6MjEwODk0Nzk1OX0.KA7A4JqoSMc__95LF-Aa-GnfIBtnOqzBioj1ZYToRLo',
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFrem5ocXpsYXFuaGVzbm1sbXpiIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc5MzM3MTk1OSwiZXhwIjoyMTA4OTQ3OTU5fQ.wqQ7JJtkP1XO6ToEK6GL_a69q8Arb5NUKML_XhzXcWA',
    jwtSecret: process.env.JWT_SECRET || 'fcQMpWjzvuQs3sq9mO733cP56ykexJNNxlvcoIOC+42SIUIsJNDRY1BIUH88+5GTJVuhMZD0fNRO8+xee7geNA==',
  },

  agora: {
    appId: process.env.AGORA_APP_ID || '2e49a7ec15bb4b29bd29576257a8ea5f',
    appCertificate: process.env.AGORA_APP_CERTIFICATE || 'dadcb0cc132941e086e74d78524c17a1',
    tokenExpiration: parseInt(process.env.AGORA_TOKEN_EXPIRATION_SECONDS || '86400', 10),
  },

  admin: {
    secretKey: process.env.ADMIN_SECRET_KEY || 'vybe-superadmin-secure-passcode',
  }
};
