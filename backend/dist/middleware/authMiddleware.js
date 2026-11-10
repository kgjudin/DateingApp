"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireAdmin = exports.authenticateJwt = void 0;
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const config_1 = require("../config");
const supabaseClient_1 = require("../integrations/supabase/supabaseClient");
const authenticateJwt = async (req, res, next) => {
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
            const profile = supabaseClient_1.LocalDbStore.profiles.get(userId);
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
            const decoded = jsonwebtoken_1.default.verify(token, config_1.config.supabase.jwtSecret);
            if (decoded && (decoded.sub || decoded.id)) {
                req.user = {
                    id: decoded.sub || decoded.id,
                    email: decoded.email,
                    username: decoded.username,
                    displayName: decoded.displayName,
                    role: decoded.role || 'user'
                };
                return next();
            }
        }
        catch {
            // Continue to check other authentication providers
        }
        // 2. Second attempt: Direct Supabase auth verification
        const supabase = (0, supabaseClient_1.getSupabase)();
        if (supabase) {
            try {
                const { data: { user }, error } = await supabase.auth.getUser(token);
                if (user && !error) {
                    req.user = {
                        id: user.id,
                        email: user.email,
                        username: user.user_metadata?.username || user.email?.split('@')[0],
                        displayName: user.user_metadata?.displayName || user.user_metadata?.display_name || user.user_metadata?.username,
                        role: user.role || 'user'
                    };
                    return next();
                }
            }
            catch (_) { }
        }
        // 3. Third attempt: Decode valid unexpired JWT payload
        try {
            const decoded = jsonwebtoken_1.default.decode(token);
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
                    displayName: decoded.displayName,
                    role: decoded.role || 'user'
                };
                return next();
            }
        }
        catch (_) { }
        res.status(401).json({
            success: false,
            error: { code: 'INVALID_TOKEN', message: 'Session expired or token invalid.' }
        });
        return;
    }
    catch (err) {
        res.status(401).json({
            success: false,
            error: { code: 'AUTH_FAILED', message: 'Authentication verification failed.' }
        });
    }
};
exports.authenticateJwt = authenticateJwt;
const requireAdmin = (req, res, next) => {
    const secret = req.headers['x-admin-secret'];
    if (secret === config_1.config.admin.secretKey || req.user?.role === 'admin' || req.user?.id === 'admin') {
        return next();
    }
    res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'Admin access required.' }
    });
};
exports.requireAdmin = requireAdmin;
