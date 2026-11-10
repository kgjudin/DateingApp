"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminController = void 0;
const supabaseClient_1 = require("../integrations/supabase/supabaseClient");
const socketHandler_1 = require("../sockets/socketHandler");
const giftController_1 = require("./giftController");
class AdminController {
    static async getDashboardStats(req, res) {
        try {
            const users = Array.from(supabaseClient_1.LocalDbStore.profiles.values());
            const totalUsers = users.length;
            const onlineUsers = Array.from(supabaseClient_1.LocalDbStore.profiles.keys()).filter(id => (0, socketHandler_1.isUserOnline)(id)).length;
            const activeCalls = Array.from(supabaseClient_1.LocalDbStore.calls.values()).filter(c => c.status === 'accepted' || c.status === 'ringing').length;
            const activeRooms = Array.from(supabaseClient_1.LocalDbStore.rooms.values()).filter(r => r.isLive).length;
            const totalGroups = supabaseClient_1.LocalDbStore.groups.size;
            const totalGiftTransactions = supabaseClient_1.LocalDbStore.giftTransactions.length;
            const totalCoinsTransacted = supabaseClient_1.LocalDbStore.giftTransactions.reduce((acc, t) => acc + (t.coinAmount || 0), 0);
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
                    recentGiftTransactions: supabaseClient_1.LocalDbStore.giftTransactions.slice(0, 10),
                    recentReports: supabaseClient_1.LocalDbStore.userReports.slice(0, 10),
                    activeRooms: Array.from(supabaseClient_1.LocalDbStore.rooms.values()).filter(r => r.isLive)
                }
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async listUsers(req, res) {
        try {
            // Sync from Supabase Auth so newly registered users immediately appear in admin roster
            const supabase = (0, supabaseClient_1.getSupabase)();
            if (supabase) {
                try {
                    const { data: authData } = await supabase.auth.admin.listUsers();
                    if (authData?.users && Array.isArray(authData.users)) {
                        for (const au of authData.users) {
                            if (!supabaseClient_1.LocalDbStore.profiles.has(au.id)) {
                                const built = (0, supabaseClient_1.buildProfileFromSupabaseUser)(au);
                                supabaseClient_1.LocalDbStore.profiles.set(au.id, built);
                            }
                            // If user_metadata says blocked, sync to memory
                            if (au.user_metadata?.isBlocked === true) {
                                supabaseClient_1.LocalDbStore.blockedUsers.add(au.id);
                            }
                        }
                    }
                }
                catch (_) { }
            }
            const users = await Promise.all(Array.from(supabaseClient_1.LocalDbStore.profiles.values()).map(async (p) => {
                const pres = (0, socketHandler_1.getUserPresence)(p.id);
                const wallet = await giftController_1.WalletService.getWallet(p.id);
                const isBlocked = supabaseClient_1.LocalDbStore.blockedUsers.has(p.id) || p.isBlocked === true || p.isSuspended === true;
                const userWarnings = supabaseClient_1.LocalDbStore.adminWarnings.filter(w => w.userId === p.id);
                return {
                    ...p,
                    status: pres.status,
                    isOnline: pres.isOnline,
                    coinBalance: wallet.balance,
                    isBlocked,
                    blockedReason: p.blockedReason || '',
                    warnings: userWarnings,
                    warningCount: userWarnings.length
                };
            }));
            // Sort: online first, then active
            users.sort((a, b) => (b.isOnline ? 1 : 0) - (a.isOnline ? 1 : 0));
            res.json({ success: true, data: users });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    /**
     * Adds coins to a user's wallet with multi-tier persistence (DB + Auth + Local + Live Socket).
     */
    static async addCoins(req, res) {
        try {
            const userId = String(req.params.userId || req.body.userId);
            const amount = Number(req.body.amount);
            const description = req.body.description || `Admin coin grant (+${amount} coins)`;
            if (!userId) {
                res.status(400).json({ success: false, error: { message: 'User ID is required.' } });
                return;
            }
            if (isNaN(amount) || amount <= 0) {
                res.status(400).json({ success: false, error: { message: 'Amount must be a positive integer.' } });
                return;
            }
            // Add coins via WalletService
            const result = await giftController_1.WalletService.addCoins(userId, amount, {
                type: 'admin_grant',
                description,
                referenceId: `adm_${Date.now()}`
            });
            // Notify user via real-time WebSocket
            const io = (0, socketHandler_1.getSocketIo)();
            if (io) {
                io.to(`user:${userId}`).emit('coin_balance_updated', {
                    newBalance: result.wallet.balance,
                    amountAdded: amount,
                    reason: description
                });
                // Add in-app notification
                const notif = {
                    id: `notif_${Date.now()}`,
                    userId,
                    title: '🪙 Coins Received!',
                    message: `Admin added ${amount} coins to your wallet. Current balance: ${result.wallet.balance} coins.`,
                    type: 'coin_grant',
                    createdAt: new Date().toISOString(),
                    isRead: false
                };
                supabaseClient_1.LocalDbStore.notifications.unshift(notif);
                io.to(`user:${userId}`).emit('notification', notif);
            }
            res.json({
                success: true,
                message: `Successfully added ${amount} coins to user.`,
                data: {
                    userId,
                    amountAdded: amount,
                    newBalance: result.wallet.balance
                }
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    /**
     * Blocks or unblocks a user from the platform (bans calling, sets blocked status).
     */
    static async toggleUserBlock(req, res) {
        try {
            const userId = String(req.params.userId || req.body.userId);
            const requestedStatus = req.body.isBlocked !== undefined ? Boolean(req.body.isBlocked) : undefined;
            const reason = req.body.reason || 'Account suspended by administrator for policy violation.';
            if (!userId) {
                res.status(400).json({ success: false, error: { message: 'User ID is required.' } });
                return;
            }
            const currentlyBlocked = supabaseClient_1.LocalDbStore.blockedUsers.has(userId);
            const willBeBlocked = requestedStatus !== undefined ? requestedStatus : !currentlyBlocked;
            if (willBeBlocked) {
                supabaseClient_1.LocalDbStore.blockedUsers.add(userId);
            }
            else {
                supabaseClient_1.LocalDbStore.blockedUsers.delete(userId);
            }
            // Update in-memory profile
            const user = supabaseClient_1.LocalDbStore.profiles.get(userId);
            if (user) {
                user.isBlocked = willBeBlocked;
                user.isSuspended = willBeBlocked;
                user.blockedReason = willBeBlocked ? reason : null;
                user.blockedAt = willBeBlocked ? new Date().toISOString() : null;
                supabaseClient_1.LocalDbStore.profiles.set(userId, user);
            }
            // Persist to disk
            supabaseClient_1.LocalDbStore.saveToDisk();
            // Persist to Supabase Auth user_metadata
            const supabase = (0, supabaseClient_1.getSupabase)();
            if (supabase) {
                try {
                    const { data } = await supabase.auth.admin.getUserById(userId);
                    if (data?.user) {
                        await supabase.auth.admin.updateUserById(userId, {
                            user_metadata: {
                                ...data.user.user_metadata,
                                isBlocked: willBeBlocked,
                                isSuspended: willBeBlocked,
                                blockedReason: willBeBlocked ? reason : null,
                                blockedAt: willBeBlocked ? new Date().toISOString() : null
                            }
                        });
                    }
                }
                catch (_) { }
            }
            // Notify user via real-time WebSocket
            const io = (0, socketHandler_1.getSocketIo)();
            if (io) {
                if (willBeBlocked) {
                    io.to(`user:${userId}`).emit('user_blocked', {
                        reason,
                        timestamp: new Date().toISOString()
                    });
                }
                else {
                    io.to(`user:${userId}`).emit('user_unblocked', {
                        message: 'Your account suspension has been lifted by the administrator.',
                        timestamp: new Date().toISOString()
                    });
                }
            }
            res.json({
                success: true,
                message: `User ${willBeBlocked ? 'blocked' : 'unblocked'} successfully.`,
                data: {
                    userId,
                    isBlocked: willBeBlocked,
                    reason: willBeBlocked ? reason : null
                }
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    /**
     * Issues an official warning to a user, recorded in their warning history and shown in-app.
     */
    static async sendWarning(req, res) {
        try {
            const userId = String(req.params.userId || req.body.userId);
            const message = String(req.body.message || '').trim();
            if (!userId) {
                res.status(400).json({ success: false, error: { message: 'User ID is required.' } });
                return;
            }
            if (!message) {
                res.status(400).json({ success: false, error: { message: 'Warning message cannot be empty.' } });
                return;
            }
            const warning = {
                id: `warn_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
                userId,
                message,
                createdAt: new Date().toISOString(),
                acknowledged: false
            };
            supabaseClient_1.LocalDbStore.adminWarnings.unshift(warning);
            supabaseClient_1.LocalDbStore.saveToDisk();
            // Persist warning history to Supabase Auth metadata
            const supabase = (0, supabaseClient_1.getSupabase)();
            if (supabase) {
                try {
                    const { data } = await supabase.auth.admin.getUserById(userId);
                    if (data?.user) {
                        const currentWarnings = Array.isArray(data.user.user_metadata?.warnings)
                            ? data.user.user_metadata.warnings
                            : [];
                        await supabase.auth.admin.updateUserById(userId, {
                            user_metadata: {
                                ...data.user.user_metadata,
                                warnings: [warning, ...currentWarnings].slice(0, 20)
                            }
                        });
                    }
                }
                catch (_) { }
            }
            // Real-time socket alert to the user's active session
            const io = (0, socketHandler_1.getSocketIo)();
            if (io) {
                io.to(`user:${userId}`).emit('admin_warning', {
                    id: warning.id,
                    message: warning.message,
                    createdAt: warning.createdAt
                });
                // Add to in-app notification center
                const notif = {
                    id: `notif_${Date.now()}`,
                    userId,
                    title: '⚠️ Admin Warning',
                    message: warning.message,
                    type: 'warning',
                    createdAt: new Date().toISOString(),
                    isRead: false
                };
                supabaseClient_1.LocalDbStore.notifications.unshift(notif);
                io.to(`user:${userId}`).emit('notification', notif);
            }
            res.json({
                success: true,
                message: 'Warning sent successfully to user.',
                data: warning
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async toggleUserSuspension(req, res) {
        return AdminController.toggleUserBlock(req, res);
    }
    static async listReports(req, res) {
        try {
            res.json({ success: true, data: supabaseClient_1.LocalDbStore.userReports });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async resolveReport(req, res) {
        try {
            const reportId = String(req.params.reportId);
            const { status, adminNotes } = req.body;
            const report = supabaseClient_1.LocalDbStore.userReports.find(r => r.id === reportId);
            if (!report) {
                res.status(404).json({ success: false, error: { message: 'Report not found' } });
                return;
            }
            report.status = status || 'resolved';
            report.adminNotes = adminNotes || 'Action taken by admin.';
            report.resolvedAt = new Date().toISOString();
            res.json({ success: true, data: report });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    // Interactive Web HTML Dashboard view
    static async renderDashboard(req, res) {
        // Sync any Supabase users
        const supabase = (0, supabaseClient_1.getSupabase)();
        if (supabase) {
            try {
                const { data: authData } = await supabase.auth.admin.listUsers();
                if (authData?.users && Array.isArray(authData.users)) {
                    for (const au of authData.users) {
                        if (!supabaseClient_1.LocalDbStore.profiles.has(au.id)) {
                            supabaseClient_1.LocalDbStore.profiles.set(au.id, (0, supabaseClient_1.buildProfileFromSupabaseUser)(au));
                        }
                        if (au.user_metadata?.isBlocked === true) {
                            supabaseClient_1.LocalDbStore.blockedUsers.add(au.id);
                        }
                    }
                }
            }
            catch (_) { }
        }
        const users = Array.from(supabaseClient_1.LocalDbStore.profiles.values());
        const onlineCount = Array.from(supabaseClient_1.LocalDbStore.profiles.keys()).filter(id => (0, socketHandler_1.isUserOnline)(id)).length;
        const activeRooms = Array.from(supabaseClient_1.LocalDbStore.rooms.values()).filter(r => r.isLive);
        const totalGifts = supabaseClient_1.LocalDbStore.giftTransactions.length;
        const totalCoins = supabaseClient_1.LocalDbStore.giftTransactions.reduce((acc, t) => acc + (t.coinAmount || 0), 0);
        const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VYBE Admin Console</title>
  <style>
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0B0B14; color: #FFFFFF; margin: 0; padding: 24px; }
    .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #1C1B2B; padding-bottom: 16px; margin-bottom: 24px; }
    .logo { font-size: 24px; font-weight: 800; background: linear-gradient(135deg, #A855F7, #EC4899); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 32px; }
    .card { background: #141421; border: 1px solid #1C1B2B; border-radius: 12px; padding: 20px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); }
    .card h3 { margin: 0 0 8px 0; font-size: 13px; color: #A1A1B5; font-weight: 500; text-transform: uppercase; }
    .card .val { font-size: 28px; font-weight: 700; color: #A855F7; }
    .section-title { font-size: 18px; margin: 28px 0 16px 0; color: #EC4899; display: flex; justify-content: space-between; align-items: center; }
    .search-box { background: #141421; border: 1px solid #2B2A3C; color: white; padding: 8px 14px; border-radius: 8px; font-size: 14px; width: 280px; }
    table { width: 100%; border-collapse: collapse; background: #141421; border-radius: 12px; overflow: hidden; margin-bottom: 30px; }
    th, td { padding: 12px 16px; text-align: left; border-bottom: 1px solid #1C1B2B; font-size: 13px; vertical-align: middle; }
    th { background: #1C1B2B; color: #A1A1B5; text-transform: uppercase; font-size: 11px; letter-spacing: 0.5px; }
    .badge { padding: 4px 8px; border-radius: 6px; font-size: 11px; font-weight: 600; display: inline-block; }
    .badge-online { background: rgba(34, 197, 94, 0.2); color: #22C55E; }
    .badge-offline { background: rgba(161, 161, 181, 0.2); color: #A1A1B5; }
    .badge-blocked { background: rgba(239, 68, 68, 0.2); color: #EF4444; border: 1px solid rgba(239, 68, 68, 0.5); }
    .badge-active { background: rgba(34, 197, 94, 0.15); color: #22C55E; }
    .badge-warn { background: rgba(245, 158, 11, 0.2); color: #F59E0B; }
    .btn { padding: 6px 12px; border-radius: 8px; border: none; font-size: 12px; font-weight: 700; cursor: pointer; transition: 0.2s; margin-right: 6px; }
    .btn-coin { background: #A855F7; color: white; }
    .btn-coin:hover { background: #9333EA; }
    .btn-block { background: rgba(239, 68, 68, 0.2); color: #EF4444; border: 1px solid #EF4444; }
    .btn-block:hover { background: #EF4444; color: white; }
    .btn-unblock { background: rgba(34, 197, 94, 0.2); color: #22C55E; border: 1px solid #22C55E; }
    .btn-unblock:hover { background: #22C55E; color: white; }
    .btn-warn { background: rgba(245, 158, 11, 0.2); color: #F59E0B; border: 1px solid #F59E0B; }
    .btn-warn:hover { background: #F59E0B; color: black; }
    .toast { position: fixed; bottom: 24px; right: 24px; background: #1C1B2B; border: 1px solid #A855F7; color: white; padding: 12px 20px; border-radius: 10px; box-shadow: 0 10px 30px rgba(0,0,0,0.8); display: none; z-index: 1000; font-size: 14px; }
  </style>
</head>
<body>
  <div class="header">
    <div class="logo">⚡ VYBE PLATFORM ADMIN CONSOLE</div>
    <div style="color: #22C55E; font-size: 14px;">● Server Status: Operational & Live</div>
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

  <div class="section-title">
    <div>User Roster & Moderation Controls</div>
    <input type="text" id="userSearch" class="search-box" placeholder="🔍 Search users by name..." onkeyup="filterUsers()">
  </div>

  <table id="usersTable">
    <thead>
      <tr>
        <th>User</th>
        <th>Username</th>
        <th>Presence</th>
        <th>Status</th>
        <th>Coins</th>
        <th>Warnings</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      ${users.map(u => {
            const pres = (0, socketHandler_1.getUserPresence)(u.id);
            const currentStatus = pres.status;
            const wal = supabaseClient_1.LocalDbStore.wallets.get(u.id);
            const coins = wal?.balance ?? 100;
            const isBlocked = supabaseClient_1.LocalDbStore.blockedUsers.has(u.id) || u.isBlocked === true;
            const userWarnings = supabaseClient_1.LocalDbStore.adminWarnings.filter(w => w.userId === u.id);
            return `
          <tr id="row-${u.id}" data-search="${(u.displayName || '') + ' ' + (u.username || '') + ' ' + (u.id || '')}">
            <td>
              <div style="display: flex; align-items: center; gap: 10px;">
                <img src="${u.avatarUrl || 'https://api.dicebear.com/7.x/avataaars/svg?seed=' + u.id}" style="width: 34px; height: 34px; border-radius: 50%; object-fit: cover;">
                <div>
                  <strong>${u.displayName || 'User'}</strong><br>
                  <span style="color: #6E6D8A; font-size: 11px;">ID: ${u.id.substring(0, 8)}...</span>
                </div>
              </div>
            </td>
            <td>@${u.username || 'vyber'}</td>
            <td><span class="badge ${currentStatus === 'online' ? 'badge-online' : 'badge-offline'}">${currentStatus}</span></td>
            <td>
              <span id="status-badge-${u.id}" class="badge ${isBlocked ? 'badge-blocked' : 'badge-active'}">
                ${isBlocked ? '🚫 Blocked' : 'Active'}
              </span>
            </td>
            <td><strong style="color: #F59E0B;">🪙 <span id="coins-${u.id}">${coins}</span></strong></td>
            <td><span id="warns-${u.id}" class="badge badge-warn">${userWarnings.length}</span></td>
            <td>
              <button class="btn btn-coin" onclick="promptAddCoins('${u.id}', '${u.displayName || 'User'}')">🪙 Add Coins</button>
              <button id="block-btn-${u.id}" class="btn ${isBlocked ? 'btn-unblock' : 'btn-block'}" onclick="toggleBlock('${u.id}', ${!isBlocked})">
                ${isBlocked ? '🟢 Unblock' : '🚫 Block'}
              </button>
              <button class="btn btn-warn" onclick="promptWarning('${u.id}', '${u.displayName || 'User'}')">⚠️ Warn</button>
            </td>
          </tr>
        `;
        }).join('')}
    </tbody>
  </table>

  <div id="toast" class="toast"></div>

  <script>
    function showToast(msg) {
      const toast = document.getElementById('toast');
      toast.innerText = msg;
      toast.style.display = 'block';
      setTimeout(() => { toast.style.display = 'none'; }, 3500);
    }

    function filterUsers() {
      const q = document.getElementById('userSearch').value.toLowerCase();
      const rows = document.querySelectorAll('#usersTable tbody tr');
      rows.forEach(r => {
        const text = r.getAttribute('data-search').toLowerCase();
        r.style.display = text.includes(q) ? '' : 'none';
      });
    }

    async function promptAddCoins(userId, name) {
      const amountStr = prompt('Add coins to ' + name + ':\\nEnter coin amount (e.g. 100, 500, 1000):', '100');
      if (!amountStr) return;
      const amount = parseInt(amountStr, 10);
      if (isNaN(amount) || amount <= 0) {
        alert('Please enter a valid positive number.');
        return;
      }

      try {
        const res = await fetch('/api/v1/admin/users/' + userId + '/coins', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ amount, description: 'Admin Grant: Added ' + amount + ' coins' })
        });
        const data = await res.json();
        if (data.success) {
          document.getElementById('coins-' + userId).innerText = data.data.newBalance;
          showToast('🪙 Successfully added ' + amount + ' coins to ' + name + '! New balance: ' + data.data.newBalance);
        } else {
          alert('Failed to add coins: ' + (data.error?.message || 'Server error'));
        }
      } catch (e) {
        alert('Network error: ' + e.message);
      }
    }

    async function toggleBlock(userId, blockTarget) {
      let reason = '';
      if (blockTarget) {
        reason = prompt('Reason for blocking this user (optional):', 'Violated community standards');
        if (reason === null) return;
      } else {
        if (!confirm('Are you sure you want to unblock this user?')) return;
      }

      try {
        const res = await fetch('/api/v1/admin/users/' + userId + '/block', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ isBlocked: blockTarget, reason: reason || 'Admin action' })
        });
        const data = await res.json();
        if (data.success) {
          const badge = document.getElementById('status-badge-' + userId);
          const btn = document.getElementById('block-btn-' + userId);
          if (blockTarget) {
            badge.className = 'badge badge-blocked';
            badge.innerText = '🚫 Blocked';
            btn.className = 'btn btn-unblock';
            btn.innerText = '🟢 Unblock';
            btn.setAttribute('onclick', "toggleBlock('" + userId + "', false)");
            showToast('🚫 User has been blocked.');
          } else {
            badge.className = 'badge badge-active';
            badge.innerText = 'Active';
            btn.className = 'btn btn-block';
            btn.innerText = '🚫 Block';
            btn.setAttribute('onclick', "toggleBlock('" + userId + "', true)");
            showToast('🟢 User has been unblocked.');
          }
        } else {
          alert('Failed to update status: ' + (data.error?.message || 'Server error'));
        }
      } catch (e) {
        alert('Network error: ' + e.message);
      }
    }

    async function promptWarning(userId, name) {
      const message = prompt('Send official warning to ' + name + ':\\nEnter warning message:', 'Please follow VYBE community guidelines. Continued violations will result in account suspension.');
      if (!message || !message.trim()) return;

      try {
        const res = await fetch('/api/v1/admin/users/' + userId + '/warning', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: message.trim() })
        });
        const data = await res.json();
        if (data.success) {
          const warnBadge = document.getElementById('warns-' + userId);
          if (warnBadge) {
            const current = parseInt(warnBadge.innerText, 10) || 0;
            warnBadge.innerText = current + 1;
          }
          showToast('⚠️ Official warning sent to ' + name + '!');
        } else {
          alert('Failed to send warning: ' + (data.error?.message || 'Server error'));
        }
      } catch (e) {
        alert('Network error: ' + e.message);
      }
    }
  </script>
</body>
</html>`;
        res.send(html);
    }
}
exports.AdminController = AdminController;
