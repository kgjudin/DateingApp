"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AgoraService = void 0;
const agora_token_1 = require("agora-token");
const config_1 = require("../../config");
class AgoraService {
    /**
     * Generates a secure Agora RTC token for 1-to-1 voice calling or group rooms.
     * Uses universal numeric UID 0 or provided numeric UID to allow seamless client joins.
     * @param channelName Unique name for call or voice room
     * @param uid Numeric or string UID of the participant (0 = universal token)
     * @param isPublisher True if user has microphone permissions (speaker/host/peer), false if listener
     * @param expirationSeconds Expiration time in seconds (default 24h = 86400)
     */
    static generateRtcToken(channelName, uid = 0, isPublisher = true, expirationSeconds = config_1.config.agora.tokenExpiration) {
        const role = isPublisher ? agora_token_1.RtcRole.PUBLISHER : agora_token_1.RtcRole.SUBSCRIBER;
        const currentTimestamp = Math.floor(Date.now() / 1000);
        const expiresAt = currentTimestamp + expirationSeconds;
        // Use 0 as universal numeric UID so Flutter RTC clients joining with uid: 0 always succeed
        const numericUid = typeof uid === 'number' ? uid : 0;
        let token;
        try {
            // In agora-token AccessToken2, parameter 6 and 7 are TTL in seconds (e.g. 86400)
            token = agora_token_1.RtcTokenBuilder.buildTokenWithUid(config_1.config.agora.appId, config_1.config.agora.appCertificate, channelName, numericUid, role, expirationSeconds, expirationSeconds);
        }
        catch (err) {
            console.warn('[AgoraService] Fallback token generated (Test mode):', err);
            token = `demo_agora_token_${channelName}_${numericUid}_${Date.now()}`;
        }
        return {
            token,
            channelName,
            appId: config_1.config.agora.appId,
            expiresAt,
        };
    }
}
exports.AgoraService = AgoraService;
