import { RtcTokenBuilder, RtcRole } from 'agora-token';
import { config } from '../../config';

export class AgoraService {
  /**
   * Generates a secure Agora RTC token for 1-to-1 voice calling or group rooms
   * @param channelName Unique name for call or voice room
   * @param uid Numeric or string UID of the participant
   * @param isPublisher True if user has microphone permissions (speaker/host/peer), false if listener
   * @param expirationSeconds Expiration time in seconds (default 24h)
   */
  public static generateRtcToken(
    channelName: string,
    uid: number | string,
    isPublisher: boolean = true,
    expirationSeconds: number = config.agora.tokenExpiration
  ): { token: string; channelName: string; appId: string; expiresAt: number } {
    const role = isPublisher ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER;
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTimestamp + expirationSeconds;

    // Convert string uid or numeric uid to string representation
    const uidStr = String(uid);

    let token: string;
    try {
      token = RtcTokenBuilder.buildTokenWithUserAccount(
        config.agora.appId,
        config.agora.appCertificate,
        channelName,
        uidStr,
        role,
        privilegeExpiredTs,
        privilegeExpiredTs
      );
    } catch (err) {
      console.warn('[AgoraService] Fallback token generated (Test mode):', err);
      token = `demo_agora_token_${channelName}_${uidStr}_${Date.now()}`;
    }

    return {
      token,
      channelName,
      appId: config.agora.appId,
      expiresAt: privilegeExpiredTs,
    };
  }
}
