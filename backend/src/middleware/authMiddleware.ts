import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config';
import { LocalDbStore, getSupabase } from '../integrations/supabase/supabaseClient';

export interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    email?: string;
    username?: string;
    role?: string;
  };
}

export const authenticateJwt = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({
        success: false,
        error: { code: 'UNAUTHORIZED', message: 'Missing or invalid Authorization header.' }
      });
      return;
    }

    const token = authHeader.split(' ')[1];

    // Handle dev test tokens
    if (token.startsWith('dev_token_')) {
      const userId = token.replace('dev_token_', '');
      const profile = LocalDbStore.profiles.get(userId);
      req.user = {
        id: userId,
        email: `${userId}@vybe.internal`,
        username: profile?.username || userId,
        role: userId === 'admin' ? 'admin' : 'user'
      };
      return next();
    }

    // Try verifying with Supabase if configured
    const supabase = getSupabase();
    if (supabase) {
      const { data: { user }, error } = await supabase.auth.getUser(token);
      if (error || !user) {
        res.status(401).json({
          success: false,
          error: { code: 'INVALID_TOKEN', message: 'Session expired or token invalid.' }
        });
        return;
      }
      req.user = {
        id: user.id,
        email: user.email,
        username: user.user_metadata?.username,
        role: user.role
      };
      return next();
    }

    // Try standard JWT decode
    try {
      const decoded = jwt.verify(token, config.supabase.jwtSecret) as any;
      req.user = {
        id: decoded.sub || decoded.id,
        email: decoded.email,
        username: decoded.username,
        role: decoded.role || 'user'
      };
      return next();
    } catch {
      res.status(401).json({
        success: false,
        error: { code: 'INVALID_TOKEN', message: 'Session expired or token invalid.' }
      });
      return;
    }
  } catch (err) {
    res.status(401).json({
      success: false,
      error: { code: 'AUTH_FAILED', message: 'Authentication verification failed.' }
    });
  }
};

export const requireAdmin = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): void => {
  const secret = req.headers['x-admin-secret'];
  if (secret === config.admin.secretKey || req.user?.role === 'admin' || req.user?.id === 'admin') {
    return next();
  }

  res.status(403).json({
    success: false,
    error: { code: 'FORBIDDEN', message: 'Admin access required.' }
  });
};
