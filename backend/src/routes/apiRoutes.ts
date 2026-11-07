import { Router } from 'express';
import { AuthController } from '../controllers/authController';
import { ProfileController } from '../controllers/profileController';
import { DiscoveryController } from '../controllers/discoveryController';
import { CallController } from '../controllers/callController';
import { FollowController } from '../controllers/followController';
import { GroupController } from '../controllers/groupController';
import { RoomController } from '../controllers/roomController';
import { GiftController, WalletController } from '../controllers/giftController';
import { ChatController } from '../controllers/chatController';
import { AdminController } from '../controllers/adminController';
import { authenticateJwt, requireAdmin } from '../middleware/authMiddleware';

const router = Router();

// Health check
router.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'VYBE Backend API',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

// Authentication
router.post('/auth/register', AuthController.register);
router.post('/auth/login', AuthController.login);
router.post('/auth/logout', authenticateJwt, AuthController.logout);
router.get('/auth/me', authenticateJwt, AuthController.getCurrentUser);

// Profiles & Preferences
router.get('/profile/:id', authenticateJwt, ProfileController.getProfile);
router.put('/profile/me/update', authenticateJwt, ProfileController.updateProfile);
router.put('/profile/me/voice-intro', authenticateJwt, ProfileController.updateVoiceIntro);
router.put('/profile/me/preferences', authenticateJwt, ProfileController.updatePreferences);

// Discovery
router.get('/discovery/feed', authenticateJwt, DiscoveryController.getDiscoveryFeed);
router.get('/discovery/search', authenticateJwt, DiscoveryController.searchUsers);

// 1-to-1 Calls
router.post('/calls/initiate', authenticateJwt, CallController.initiateCall);
router.post('/calls/accept', authenticateJwt, CallController.acceptCall);
router.post('/calls/decline', authenticateJwt, CallController.declineCall);
router.post('/calls/end', authenticateJwt, CallController.endCall);
router.get('/calls/history', authenticateJwt, CallController.getCallHistory);

// Favourites
router.post('/favourites/toggle', authenticateJwt, CallController.toggleFavourite);
router.get('/favourites', authenticateJwt, CallController.getFavourites);

// Follow & Network
router.post('/follow/toggle', authenticateJwt, FollowController.toggleFollow);
router.get('/follow/followers/:userId', authenticateJwt, FollowController.getFollowers);
router.get('/follow/followers', authenticateJwt, FollowController.getFollowers);
router.get('/follow/following/:userId', authenticateJwt, FollowController.getFollowing);
router.get('/follow/following', authenticateJwt, FollowController.getFollowing);

// Groups
router.get('/groups', authenticateJwt, GroupController.listGroups);
router.get('/groups/:id', authenticateJwt, GroupController.getGroupDetails);
router.post('/groups/create', authenticateJwt, GroupController.createGroup);
router.post('/groups/:id/join', authenticateJwt, GroupController.joinGroup);

// Live Group Rooms
router.get('/rooms/live', authenticateJwt, RoomController.listLiveRooms);
router.post('/rooms/create', authenticateJwt, RoomController.createRoom);
router.post('/rooms/:id/join', authenticateJwt, RoomController.joinRoom);
router.post('/rooms/:id/raise-hand', authenticateJwt, RoomController.raiseHand);
router.post('/rooms/:id/approve-speaker', authenticateJwt, RoomController.approveSpeaker);
router.post('/rooms/:id/leave', authenticateJwt, RoomController.leaveRoom);

// Gifts & Wallet
router.get('/gifts/catalogue', authenticateJwt, GiftController.getGiftCatalogue);
router.post('/gifts/send', authenticateJwt, GiftController.sendGift);
router.get('/gifts/received', authenticateJwt, GiftController.getReceivedGifts);
router.get('/gifts/sent', authenticateJwt, GiftController.getSentGifts);
router.get('/wallet', authenticateJwt, WalletController.getWallet);
router.post('/wallet/purchase', authenticateJwt, WalletController.purchaseCoins);

// Chat & Moderation
router.get('/chat/conversations', authenticateJwt, ChatController.getConversations);
router.get('/chat/:otherUserId/messages', authenticateJwt, ChatController.getMessages);
router.post('/chat/send', authenticateJwt, ChatController.sendMessage);
router.post('/chat/block', authenticateJwt, ChatController.blockUser);
router.post('/chat/report', authenticateJwt, ChatController.reportUser);
router.get('/notifications', authenticateJwt, ChatController.getNotifications);

// Admin Console API & Dashboard
router.get('/admin/stats', AdminController.getDashboardStats);
router.get('/admin/users', AdminController.listUsers);
router.post('/admin/users/:userId/suspend', AdminController.toggleUserSuspension);
router.get('/admin/reports', AdminController.listReports);
router.post('/admin/reports/:reportId/resolve', AdminController.resolveReport);
router.get('/admin/dashboard', AdminController.renderDashboard);

export default router;
