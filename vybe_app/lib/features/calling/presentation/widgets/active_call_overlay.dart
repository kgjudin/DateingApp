import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../calling_controller.dart';

/// App-level persistent "Return to Call" overlay.
///
/// This widget wraps the entire MaterialApp child (via MaterialApp.router's
/// builder) and shows a floating banner whenever a call is active and the
/// user is NOT already on the /calling screen.
///
/// Design decision: we use the router's current path to decide visibility
/// rather than the [CallingState.isCallScreenVisible] flag, because on web
/// the browser back-button may not synchronously update that flag before
/// this widget rebuilds.
class ActiveCallOverlayWrapper extends ConsumerWidget {
  final Widget? child;

  const ActiveCallOverlayWrapper({super.key, required this.child});

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callingState = ref.watch(callingControllerProvider);
    final router = ref.watch(appRouterProvider);

    // Determine whether the user is currently ON the calling screen.
    final String currentPath =
        router.routerDelegate.currentConfiguration.uri.path;
    final bool onCallingScreen = currentPath == '/calling';

    // A call is "active" (not idle/ended/failed) when any of these statuses hold.
    final bool callIsActive = callingState.status == CallStatus.connected ||
        callingState.status == CallStatus.connecting ||
        callingState.status == CallStatus.ringing ||
        callingState.status == CallStatus.initiating;

    // Show the floating banner any time there is an active call and the user
    // is NOT already looking at the calling screen.
    final bool showBanner = callIsActive && !onCallingScreen;

    final peer = callingState.peerProfile ?? {};
    final peerName = peer['displayName']?.toString() ?? 'Active Call';
    final peerAvatar = peer['avatarUrl']?.toString() ??
        'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500';

    final bool isConnected = callingState.status == CallStatus.connected;
    final String statusText = isConnected
        ? _formatDuration(callingState.durationSeconds)
        : (callingState.status == CallStatus.ringing ? 'Ringing...' : 'Calling...');

    void returnToCall() {
      // Mark the call screen visible so the banner hides once we arrive.
      ref.read(callingControllerProvider.notifier).setCallScreenVisible(true);
      try {
        router.push('/calling');
      } catch (_) {
        router.go('/calling');
      }
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          if (child != null) child!,

          // ── Active Call Floating Banner ──────────────────────────────────
          if (showBanner)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 10,
              right: 10,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: returnToCall,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1F1138), Color(0xFF131524)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isConnected
                            ? AppColors.online
                            : AppColors.primaryAccent,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isConnected
                                  ? AppColors.online
                                  : AppColors.primaryAccent)
                              .withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Avatar with live status dot
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundImage: NetworkImage(peerAvatar),
                              backgroundColor: AppColors.primaryAccent,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: isConnected
                                      ? AppColors.online
                                      : AppColors.busy,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.black, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),

                        // Name & status text
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      peerName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text('🔊',
                                      style: TextStyle(fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: (isConnected
                                              ? AppColors.online
                                              : AppColors.primaryAccent)
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      statusText,
                                      style: TextStyle(
                                        color: isConnected
                                            ? AppColors.online
                                            : AppColors.primaryAccentLight,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Tap to return',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Return to Call button
                        ElevatedButton.icon(
                          onPressed: returnToCall,
                          icon: const Icon(Icons.phone_in_talk_rounded,
                              size: 14, color: Colors.white),
                          label: const Text(
                            'Return',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isConnected
                                ? AppColors.online
                                : AppColors.primaryAccent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Quick End Call button
                        GestureDetector(
                          onTap: () =>
                              ref
                                  .read(callingControllerProvider.notifier)
                                  .endCall(),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.call_end_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
