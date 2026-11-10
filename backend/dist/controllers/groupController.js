"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GroupController = void 0;
const supabaseClient_1 = require("../integrations/supabase/supabaseClient");
class GroupController {
    static async listGroups(req, res) {
        try {
            const { category } = req.query;
            let groups = Array.from(supabaseClient_1.LocalDbStore.groups.values());
            if (category && category !== 'All') {
                groups = groups.filter(g => g.category.toLowerCase() === category.toLowerCase());
            }
            res.json({ success: true, data: groups });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async getGroupDetails(req, res) {
        try {
            const id = String(req.params.id);
            const group = supabaseClient_1.LocalDbStore.groups.get(id);
            if (!group) {
                res.status(404).json({ success: false, error: { message: 'Group not found' } });
                return;
            }
            // Check for active room in this group
            let activeRoom = null;
            for (const r of supabaseClient_1.LocalDbStore.rooms.values()) {
                if (r.groupId === id && r.isLive) {
                    activeRoom = r;
                    break;
                }
            }
            res.json({
                success: true,
                data: {
                    ...group,
                    activeRoom
                }
            });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async createGroup(req, res) {
        try {
            const userId = req.user?.id;
            if (!userId) {
                res.status(401).json({ success: false, error: { message: 'Unauthorized' } });
                return;
            }
            const { name, description, category, avatarUrl, coverUrl, rules, isPrivate } = req.body;
            if (!name) {
                res.status(400).json({ success: false, error: { message: 'Group name is required' } });
                return;
            }
            const groupId = `grp_${Date.now()}`;
            const newGroup = {
                id: groupId,
                name,
                description: description || '',
                category: category || 'General Conversations',
                avatarUrl: avatarUrl || 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=500&auto=format&fit=crop&q=80',
                coverUrl: coverUrl || 'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?w=1000&auto=format&fit=crop&q=80',
                ownerId: userId,
                totalMembers: 1,
                isPrivate: isPrivate || false,
                rules: rules || 'Be kind, respect speaker turns, and have fun!',
                createdAt: new Date().toISOString()
            };
            supabaseClient_1.LocalDbStore.groups.set(groupId, newGroup);
            res.status(201).json({ success: true, data: newGroup });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
    static async joinGroup(req, res) {
        try {
            const id = String(req.params.id);
            const group = supabaseClient_1.LocalDbStore.groups.get(id);
            if (!group) {
                res.status(404).json({ success: false, error: { message: 'Group not found' } });
                return;
            }
            group.totalMembers = (group.totalMembers || 0) + 1;
            supabaseClient_1.LocalDbStore.groups.set(id, group);
            res.json({ success: true, message: 'Joined group successfully', data: group });
        }
        catch (err) {
            res.status(500).json({ success: false, error: { message: err.message } });
        }
    }
}
exports.GroupController = GroupController;
