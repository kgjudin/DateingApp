"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const authController_1 = require("../controllers/authController");
const profileController_1 = require("../controllers/profileController");
const discoveryController_1 = require("../controllers/discoveryController");
const callController_1 = require("../controllers/callController");
const followController_1 = require("../controllers/followController");
const groupController_1 = require("../controllers/groupController");
const roomController_1 = require("../controllers/roomController");
const giftController_1 = require("../controllers/giftController");
const chatController_1 = require("../controllers/chatController");
const adminController_1 = require("../controllers/adminController");
const authMiddleware_1 = require("../middleware/authMiddleware");
const router = (0, express_1.Router)();
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
router.post('/auth/register', authController_1.AuthController.register);
router.post('/auth/login', authController_1.AuthController.login);
router.post('/auth/logout', authMiddleware_1.authenticateJwt, authController_1.AuthController.logout);
router.get('/auth/me', authMiddleware_1.authenticateJwt, authController_1.AuthController.getCurrentUser);
// Profiles & Preferences
router.get('/profile/:id', authMiddleware_1.authenticateJwt, profileController_1.ProfileController.getProfile);
router.put('/profile/me/update', authMiddleware_1.authenticateJwt, profileController_1.ProfileController.updateProfile);
router.put('/profile/me/voice-intro', authMiddleware_1.authenticateJwt, profileController_1.ProfileController.updateVoiceIntro);
router.put('/profile/me/preferences', authMiddleware_1.authenticateJwt, profileController_1.ProfileController.updatePreferences);
// Discovery
router.get('/discovery/feed', authMiddleware_1.authenticateJwt, discoveryController_1.DiscoveryController.getDiscoveryFeed);
router.get('/discovery/search', authMiddleware_1.authenticateJwt, discoveryController_1.DiscoveryController.searchUsers);
// 1-to-1 Calls
router.post('/calls/initiate', authMiddleware_1.authenticateJwt, callController_1.CallController.initiateCall);
router.post('/calls/accept', authMiddleware_1.authenticateJwt, callController_1.CallController.acceptCall);
router.post('/calls/decline', authMiddleware_1.authenticateJwt, callController_1.CallController.declineCall);
router.post('/calls/end', authMiddleware_1.authenticateJwt, callController_1.CallController.endCall);
router.get('/calls/history', authMiddleware_1.authenticateJwt, callController_1.CallController.getCallHistory);
// Favourites
router.post('/favourites/toggle', authMiddleware_1.authenticateJwt, callController_1.CallController.toggleFavourite);
router.get('/favourites', authMiddleware_1.authenticateJwt, callController_1.CallController.getFavourites);
// Follow & Network
router.post('/follow/toggle', authMiddleware_1.authenticateJwt, followController_1.FollowController.toggleFollow);
router.get('/follow/followers/:userId', authMiddleware_1.authenticateJwt, followController_1.FollowController.getFollowers);
router.get('/follow/followers', authMiddleware_1.authenticateJwt, followController_1.FollowController.getFollowers);
router.get('/follow/following/:userId', authMiddleware_1.authenticateJwt, followController_1.FollowController.getFollowing);
router.get('/follow/following', authMiddleware_1.authenticateJwt, followController_1.FollowController.getFollowing);
// Groups
router.get('/groups', authMiddleware_1.authenticateJwt, groupController_1.GroupController.listGroups);
router.get('/groups/:id', authMiddleware_1.authenticateJwt, groupController_1.GroupController.getGroupDetails);
router.post('/groups/create', authMiddleware_1.authenticateJwt, groupController_1.GroupController.createGroup);
router.post('/groups/:id/join', authMiddleware_1.authenticateJwt, groupController_1.GroupController.joinGroup);
// Live Group Rooms
router.get('/rooms/live', authMiddleware_1.authenticateJwt, roomController_1.RoomController.listLiveRooms);
router.post('/rooms/create', authMiddleware_1.authenticateJwt, roomController_1.RoomController.createRoom);
router.get('/rooms/:id', authMiddleware_1.authenticateJwt, roomController_1.RoomController.getRoomDetails);
router.post('/rooms/:id/join', authMiddleware_1.authenticateJwt, roomController_1.RoomController.joinRoom);
router.post('/rooms/:id/raise-hand', authMiddleware_1.authenticateJwt, roomController_1.RoomController.raiseHand);
router.post('/rooms/:id/lower-hand', authMiddleware_1.authenticateJwt, roomController_1.RoomController.lowerHand);
router.post('/rooms/:id/approve-speaker', authMiddleware_1.authenticateJwt, roomController_1.RoomController.approveSpeaker);
router.post('/rooms/:id/invite-to-speak', authMiddleware_1.authenticateJwt, roomController_1.RoomController.inviteToSpeak);
router.post('/rooms/:id/accept-invitation', authMiddleware_1.authenticateJwt, roomController_1.RoomController.acceptInvitation);
router.post('/rooms/:id/mute-speaker', authMiddleware_1.authenticateJwt, roomController_1.RoomController.muteSpeaker);
router.post('/rooms/:id/demote-speaker', authMiddleware_1.authenticateJwt, roomController_1.RoomController.demoteSpeaker);
router.post('/rooms/:id/kick-user', authMiddleware_1.authenticateJwt, roomController_1.RoomController.kickUser);
router.post('/rooms/:id/make-subhost', authMiddleware_1.authenticateJwt, roomController_1.RoomController.makeSubHost);
router.post('/rooms/:id/leave', authMiddleware_1.authenticateJwt, roomController_1.RoomController.leaveRoom);
// Gifts & Wallet
router.get('/gifts/catalogue', authMiddleware_1.authenticateJwt, giftController_1.GiftController.getGiftCatalogue);
router.post('/gifts/send', authMiddleware_1.authenticateJwt, giftController_1.GiftController.sendGift);
router.get('/gifts/received', authMiddleware_1.authenticateJwt, giftController_1.GiftController.getReceivedGifts);
router.get('/gifts/sent', authMiddleware_1.authenticateJwt, giftController_1.GiftController.getSentGifts);
router.get('/wallet', authMiddleware_1.authenticateJwt, giftController_1.WalletController.getWallet);
router.get('/wallet/balance', authMiddleware_1.authenticateJwt, giftController_1.WalletController.getBalance);
router.post('/wallet/purchase', authMiddleware_1.authenticateJwt, giftController_1.WalletController.purchaseCoins);
router.post('/wallet/recharge', authMiddleware_1.authenticateJwt, giftController_1.WalletController.purchaseCoins);
router.post('/wallet/deduct', authMiddleware_1.authenticateJwt, giftController_1.WalletController.deductCoins);
router.post('/wallet/spend', authMiddleware_1.authenticateJwt, giftController_1.WalletController.deductCoins);
// Chat & Moderation
router.get('/chat/conversations', authMiddleware_1.authenticateJwt, chatController_1.ChatController.getConversations);
router.get('/chat/:otherUserId/messages', authMiddleware_1.authenticateJwt, chatController_1.ChatController.getMessages);
router.post('/chat/send', authMiddleware_1.authenticateJwt, chatController_1.ChatController.sendMessage);
router.post('/chat/block', authMiddleware_1.authenticateJwt, chatController_1.ChatController.blockUser);
router.post('/chat/report', authMiddleware_1.authenticateJwt, chatController_1.ChatController.reportUser);
router.get('/notifications', authMiddleware_1.authenticateJwt, chatController_1.ChatController.getNotifications);
router.post('/notifications/mark-read', authMiddleware_1.authenticateJwt, chatController_1.ChatController.markAllAsRead);
router.post('/notifications/clear', authMiddleware_1.authenticateJwt, chatController_1.ChatController.clearNotifications);
router.delete('/notifications/clear', authMiddleware_1.authenticateJwt, chatController_1.ChatController.clearNotifications);
// Admin Console API & Dashboard
router.get('/admin/stats', adminController_1.AdminController.getDashboardStats);
router.get('/admin/users', adminController_1.AdminController.listUsers);
router.post('/admin/users/:userId/suspend', adminController_1.AdminController.toggleUserSuspension);
router.get('/admin/reports', adminController_1.AdminController.listReports);
router.post('/admin/reports/:reportId/resolve', adminController_1.AdminController.resolveReport);
router.get('/admin/dashboard', adminController_1.AdminController.renderDashboard);
exports.default = router;
