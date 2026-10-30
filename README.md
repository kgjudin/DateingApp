# VYBE – Voice-First Social Discovery & Communication Platform

<div align="center">
  <img src="https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=1000&auto=format&fit=crop&q=80" width="100%" height="260" style="object-fit: cover; border-radius: 16px;" />
  <br/><br/>
  <h1>⚡ VYBE</h1>
  <p><strong>A Production-Ready Voice-First Social Discovery & Real-Time Audio Platform</strong></p>
  <p><em>Spontaneous 1-to-1 Voice Calls • Clubhouse-Style Group Stages • Interest-Based Radar • Virtual Gifts & Secure Ledger</em></p>
</div>

---

## 🌟 Executive Summary

**VYBE is NOT a dating application.** It is a modern, voice-first social discovery platform designed to foster real human connections through spontaneous voice calls, interest-driven discovery, and Clubhouse-style group audio stages.

### Core Value Pillars
1. **Voice-First Social Radar**: Real-time discovery based on online presence, shared interests, and discovery preferences.
2. **Instant 1-to-1 Voice Calling**: Full-duplex audio calling powered by Agora RTC with dynamic tokens generated exclusively on the backend.
3. **Clubhouse-Style Live Audio Rooms**: Multi-speaker stages featuring Host, Co-host, Speaker, and Listener roles, with raise-hand requests and audience participation.
4. **Virtual Gifting & Secure Coin Wallet**: Cryptographically secure ledger preventing client-side tampering, backed by atomic database transactions.
5. **Safety, Privacy & Moderation**: Adult 18+ platform with consent controls, block lists, report handling, and an administrative web dashboard.

---

## 🏗️ Technology Stack

| Layer | Technologies |
|---|---|
| **Mobile Frontend** | Flutter (Dart 3.x), Riverpod, GoRouter, Google Fonts, Flutter Animate |
| **Backend & APIs** | Node.js, Express.js, TypeScript, Helmet, Morgan, Zod |
| **Voice & RTC Engine** | Agora RTC Engine (`agora_rtc_engine` & `agora-token`) |
| **Realtime & Signaling** | Socket.IO Server & Client, Supabase Realtime |
| **Database & Auth** | Supabase PostgreSQL (26 Tables with RLS), Stored Procedures & Triggers |
| **Storage & Push** | Supabase Storage (Covers, Avatars, Voice Intros), Firebase Cloud Messaging |

---

## 🎨 Design System & Aesthetic

VYBE follows a **Midnight Dark Aesthetic**:

* **Primary Background**: `#0B0B14` (Deep Midnight Canvas)
* **Secondary Surface**: `#141421` (Elevated Panels)
* **Card Surface**: `#1C1B2B` (Glassmorphic Modals & Cards)
* **Primary Accent**: `#A855F7` (Electric Violet)
* **Secondary Accent**: `#EC4899` (Neon Rose / Pink)
* **Online Glow Indicator**: `#22C55E` (Emerald Active Presence)
* **Text**: `#FFFFFF` (Headings) / `#A1A1B5` (Muted Metadata)

---

## 📂 Repository Architecture

```
Date/
├── backend/                             # Node.js TypeScript API & Signaling Server
│   ├── src/
│   │   ├── config/                     # Environment configuration
│   │   ├── controllers/                # Auth, Profile, Discovery, Calls, Rooms, Gifts, Admin
│   │   ├── integrations/
│   │   │   ├── agora/                  # Dynamic Agora RTC token generator
│   │   │   └── supabase/               # Supabase client & in-memory test store
│   │   ├── middleware/                 # JWT Auth & Admin permission guards
│   │   ├── routes/                     # REST API v1 routing table
│   │   ├── sockets/                    # Socket.IO signaling, heartbeats & presence
│   │   ├── app.ts                      # Express app setup
│   │   └── server.ts                   # HTTP + WebSocket server bootstrap
│   ├── package.json
│   ├── tsconfig.json
│   └── .env.example
│
├── database/                            # Supabase PostgreSQL Migrations
│   ├── 01_schema.sql                   # 26 tables, custom types, enums & indexes
│   ├── 02_functions_and_triggers.sql   # Atomic gift transfer, presence heartbeat & RLS policies
│   └── 03_seed.sql                     # Seed categories, interests & default virtual gifts
│
└── vybe_app/                            # Flutter Mobile Application
    ├── lib/
    │   ├── core/
    │   │   ├── constants/              # URLs & keys
    │   │   ├── network/                # ApiClient & SocketService
    │   │   ├── router/                 # GoRouter declarations
    │   │   ├── theme/                  # AppColors & Dark ThemeData
    │   │   ├── voice/                  # AgoraVoiceService (RTC wrapper)
    │   │   └── widgets/                # GlassContainer, GradientButton, Waveform, OnlineBadge
    │   ├── features/
    │   │   ├── auth/                   # Onboarding, Login, AuthController
    │   │   ├── discovery/              # Home radar, gender filters, online carousel
    │   │   ├── profile/                # Multi-step Profile Builder & details viewer
    │   │   ├── calling/                # 1-on-1 full screen call screen & call history
    │   │   ├── groups/                 # Live Voice Rooms & Clubhouse stage
    │   │   ├── wallet/                 # Coin balance, gifts bottom sheet & ledger
    │   │   ├── chat/                   # Direct messaging
    │   │   ├── notifications/          # Realtime notification center
    │   │   └── main_shell.dart         # Custom floating bottom navigation
    │   └── main.dart                   # Application entry point
    └── pubspec.yaml
```

---

## 🚀 Quickstart & Setup Guide

### 1. Database Setup (Supabase)
1. Create a new project in [Supabase](https://supabase.com).
2. Open the **SQL Editor** in the Supabase Dashboard.
3. Run the migrations in order:
   - `database/01_schema.sql`
   - `database/02_functions_and_triggers.sql`
   - `database/03_seed.sql`

### 2. Backend Setup
1. Navigate to the `backend` directory:
   ```bash
   cd backend
   ```
2. Install dependencies:
   ```bash
   npm install
   ```
3. Copy `.env.example` to `.env` and fill in your keys:
   ```bash
   cp .env.example .env
   ```
4. Build and start the server:
   ```bash
   npm run build
   npm start
   ```
   * Server runs on `http://localhost:5000`
   * Web Admin Console: `http://localhost:5000/api/v1/admin/dashboard`

### 3. Flutter Client Setup
1. Navigate to `vybe_app`:
   ```bash
   cd vybe_app
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run on your target device (Android / iOS / Web):
   ```bash
   flutter run
   ```

---

## 🔒 Security Best Practices
- **No Client-Side Token Generation**: All Agora RTC tokens are generated securely on the Node.js backend using user accounts and timestamped expiration.
- **Transactional Coin Wallet**: Wallet balances cannot be updated directly from the mobile app. All deductions and gift transfers execute inside PostgreSQL atomic stored procedures (`transfer_gift_coins`) with row locking (`FOR UPDATE`).
- **Presence Heartbeat**: Online status is maintained via WebSocket heartbeats; disconnecting transitions the user to offline within 30 seconds.


# DateingApp
