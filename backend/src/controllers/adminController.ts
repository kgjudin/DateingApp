import { Request, Response } from 'express';
import { LocalDbStore } from '../integrations/supabase/supabaseClient';
import { isUserOnline, getUserPresence } from '../sockets/socketHandler';

export class AdminController {
  public static async getDashboardStats(req: Request, res: Response): Promise<void> {
    try {
      const users = Array.from(LocalDbStore.profiles.values());
      const totalUsers = users.length;
      const onlineUsers = Array.from(LocalDbStore.profiles.keys()).filter(id => isUserOnline(id)).length;
      const activeCalls = Array.from(LocalDbStore.calls.values()).filter(c => c.status === 'accepted' || c.status === 'ringing').length;
      const activeRooms = Array.from(LocalDbStore.rooms.values()).filter(r => r.isLive).length;
      const totalGroups = LocalDbStore.groups.size;
      const totalGiftTransactions = LocalDbStore.giftTransactions.length;
      
      const totalCoinsTransacted = LocalDbStore.giftTransactions.reduce((acc, t) => acc + (t.coinAmount || 0), 0);
      const estimatedRevenueUsd = (totalCoinsTransacted * 0.01).toFixed(2); // 100 coins = $1

      res.json({
        success: true,
        data: {
          metrics: {
            totalUsers,
            onlineUsers,
            activeCalls,
            activeRooms,
            totalGroups,
            totalGiftTransactions,
            totalCoinsTransacted,
            estimatedRevenueUsd
          },
          recentGiftTransactions: LocalDbStore.giftTransactions.slice(0, 10),
          recentReports: LocalDbStore.userReports.slice(0, 10),
          activeRooms: Array.from(LocalDbStore.rooms.values()).filter(r => r.isLive)
        }
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async listUsers(req: Request, res: Response): Promise<void> {
    try {
      const users = Array.from(LocalDbStore.profiles.values()).map(p => {
        const pres = getUserPresence(p.id);
        const wallet = LocalDbStore.wallets.get(p.id) || { balance: 0 };
        return {
          ...p,
          status: pres.status,
          isOnline: pres.isOnline,
          coinBalance: wallet.balance
        };
      });

      res.json({ success: true, data: users });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async toggleUserSuspension(req: Request, res: Response): Promise<void> {
    try {
      const userId = String(req.params.userId);
      const user = LocalDbStore.profiles.get(userId);

      if (!user) {
        res.status(404).json({ success: false, error: { message: 'User not found' } });
        return;
      }

      user.isSuspended = !user.isSuspended;
      LocalDbStore.profiles.set(userId, user);

      res.json({
        success: true,
        message: `User ${user.isSuspended ? 'suspended' : 'activated'} successfully.`,
        data: user
      });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async listReports(req: Request, res: Response): Promise<void> {
    try {
      res.json({ success: true, data: LocalDbStore.userReports });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  public static async resolveReport(req: Request, res: Response): Promise<void> {
    try {
      const reportId = String(req.params.reportId);
      const { status, adminNotes } = req.body;

      const report = LocalDbStore.userReports.find(r => r.id === reportId);
      if (!report) {
        res.status(404).json({ success: false, error: { message: 'Report not found' } });
        return;
      }

      report.status = status || 'resolved';
      report.adminNotes = adminNotes || 'Action taken by admin.';
      report.resolvedAt = new Date().toISOString();

      res.json({ success: true, data: report });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }

  // HTML Dashboard view
  public static async renderDashboard(req: Request, res: Response): Promise<void> {
    const users = Array.from(LocalDbStore.profiles.values());
    const onlineCount = Array.from(LocalDbStore.profiles.keys()).filter(id => isUserOnline(id)).length;
    const activeRooms = Array.from(LocalDbStore.rooms.values()).filter(r => r.isLive);
    const totalGifts = LocalDbStore.giftTransactions.length;
    const totalCoins = LocalDbStore.giftTransactions.reduce((acc, t) => acc + (t.coinAmount || 0), 0);

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>VYBE Admin Console</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0B0B14; color: #FFFFFF; margin: 0; padding: 24px; }
    .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #1C1B2B; padding-bottom: 16px; margin-bottom: 24px; }
    .logo { font-size: 24px; font-weight: 800; background: linear-gradient(135deg, #A855F7, #EC4899); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin-bottom: 32px; }
    .card { background: #141421; border: 1px solid #1C1B2B; border-radius: 12px; padding: 20px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); }
    .card h3 { margin: 0 0 8px 0; font-size: 14px; color: #A1A1B5; font-weight: 500; }
    .card .val { font-size: 28px; font-weight: 700; color: #A855F7; }
    .section-title { font-size: 18px; margin: 24px 0 16px 0; color: #EC4899; }
    table { width: 100%; border-collapse: collapse; background: #141421; border-radius: 12px; overflow: hidden; }
    th, td { padding: 12px 16px; text-align: left; border-bottom: 1px solid #1C1B2B; font-size: 14px; }
    th { background: #1C1B2B; color: #A1A1B5; text-transform: uppercase; font-size: 12px; }
    .badge { padding: 4px 8px; border-radius: 6px; font-size: 11px; font-weight: 600; }
    .badge-online { background: rgba(34, 197, 94, 0.2); color: #22C55E; }
    .badge-offline { background: rgba(161, 161, 181, 0.2); color: #A1A1B5; }
    .badge-live { background: rgba(236, 72, 153, 0.2); color: #EC4899; }
  </style>
</head>
<body>
  <div class="header">
    <div class="logo">⚡ VYBE PLATFORM ADMIN</div>
    <div style="color: #22C55E; font-size: 14px;">● Server Status: Healthy</div>
  </div>

  <div class="grid">
    <div class="card">
      <h3>TOTAL REGISTERED USERS</h3>
      <div class="val">${users.length}</div>
    </div>
    <div class="card">
      <h3>ONLINE USERS</h3>
      <div class="val" style="color: #22C55E;">${onlineCount}</div>
    </div>
    <div class="card">
      <h3>LIVE AUDIO ROOMS</h3>
      <div class="val" style="color: #EC4899;">${activeRooms.length}</div>
    </div>
    <div class="card">
      <h3>COINS TRANSACTED</h3>
      <div class="val">${totalCoins.toLocaleString()}</div>
    </div>
    <div class="card">
      <h3>GIFT VOLUME</h3>
      <div class="val">${totalGifts}</div>
    </div>
  </div>

  <div class="section-title">Active Live Clubhouse Voice Rooms</div>
  <table>
    <thead>
      <tr>
        <th>Room Title</th>
        <th>Host</th>
        <th>Topic</th>
        <th>Speakers</th>
        <th>Listeners</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
      ${activeRooms.map(r => `
        <tr>
          <td><strong>${r.title}</strong></td>
          <td>${r.hostName}</td>
          <td>${r.topic}</td>
          <td>${r.speakersCount}</td>
          <td>${r.listenersCount}</td>
          <td><span class="badge badge-live">● LIVE</span></td>
        </tr>
      `).join('')}
    </tbody>
  </table>

  <div class="section-title">User Roster & Online Presence</div>
  <table>
    <thead>
      <tr>
        <th>Name</th>
        <th>Username</th>
        <th>Gender</th>
        <th>Location</th>
        <th>Coins</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
      ${users.map(u => {
        const pres = getUserPresence(u.id);
        const currentStatus = pres.status;
        const wal = LocalDbStore.wallets.get(u.id);
        return `
          <tr>
            <td><strong>${u.displayName}</strong></td>
            <td>@${u.username}</td>
            <td>${u.gender}</td>
            <td>${u.location || 'Online'}</td>
            <td>🪙 ${wal?.balance || 0}</td>
            <td><span class="badge ${currentStatus === 'online' ? 'badge-online' : 'badge-offline'}">${currentStatus}</span></td>
          </tr>
        `;
      }).join('')}
    </tbody>
  </table>
</body>
</html>`;

    res.send(html);
  }
}
