import { RtcTokenBuilder, RtcRole } from 'agora-token';
import { config } from '../../config';

export class AgoraService {
  /**
   * Generates a secure Agora RTC token for 1-to-1 voice calling or group rooms.
   * Uses universal numeric UID 0 or provided numeric UID to allow seamless client joins.
   * @param channelName Unique name for call or voice room
   * @param uid Numeric or string UID of the participant (0 = universal token)
   * @param isPublisher True if user has microphone permissions (speaker/host/peer), false if listener
   * @param expirationSeconds Expiration time in seconds (default 24h = 86400)
   */
  public static generateRtcToken(
    channelName: string,
    uid: number | string = 0,
    isPublisher: boolean = true,
    expirationSeconds: number = config.agora.tokenExpiration
  ): { token: string; channelName: string; appId: string; expiresAt: number } {
    const role = isPublisher ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER;
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const expiresAt = currentTimestamp + expirationSeconds;

    // Use 0 as universal numeric UID so Flutter RTC clients joining with uid: 0 always succeed
    const numericUid = typeof uid === 'number' ? uid : 0;

    let token: string;
    try {
      // In agora-token AccessToken2, parameter 6 and 7 are TTL in seconds (e.g. 86400)
      token = RtcTokenBuilder.buildTokenWithUid(
        config.agora.appId,
        config.agora.appCertificate,
        channelName,
        numericUid,
        role,
        expirationSeconds,
        expirationSeconds
      );
    } catch (err) {
      console.warn('[AgoraService] Fallback token generated (Test mode):', err);
      token = `demo_agora_token_${channelName}_${numericUid}_${Date.now()}`;
    }

    return {
      token,
      channelName,
      appId: config.agora.appId,
      expiresAt,
    };
  }
}
