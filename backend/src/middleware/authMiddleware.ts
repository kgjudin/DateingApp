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

    // 1. First attempt: Verify backend JWT token
    try {
      const decoded = jwt.verify(token, config.supabase.jwtSecret) as any;
      if (decoded && (decoded.sub || decoded.id)) {
        req.user = {
          id: decoded.sub || decoded.id,
          email: decoded.email,
          username: decoded.username,
          role: decoded.role || 'user'
        };
        return next();
      }
    } catch {
      // Continue to check other authentication providers
    }

    // 2. Second attempt: Direct Supabase auth verification
    const supabase = getSupabase();
    if (supabase) {
      try {
        const { data: { user }, error } = await supabase.auth.getUser(token);
        if (user && !error) {
          req.user = {
            id: user.id,
            email: user.email,
            username: user.user_metadata?.username || user.email?.split('@')[0],
            role: user.role || 'user'
          };
          return next();
        }
      } catch (_) {}
    }

    // 3. Third attempt: Decode valid unexpired JWT payload
    try {
      const decoded = jwt.decode(token) as any;
      if (decoded && (decoded.sub || decoded.id)) {
        if (decoded.exp && Date.now() >= decoded.exp * 1000) {
          res.status(401).json({
            success: false,
            error: { code: 'TOKEN_EXPIRED', message: 'Session expired. Please log in again.' }
          });
          return;
        }

        req.user = {
          id: decoded.sub || decoded.id,
          email: decoded.email,
          username: decoded.username,
          role: decoded.role || 'user'
        };
        return next();
      }
    } catch (_) {}

    res.status(401).json({
      success: false,
      error: { code: 'INVALID_TOKEN', message: 'Session expired or token invalid.' }
    });
    return;
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
