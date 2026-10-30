import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../../core/widgets/voice_waveform_widget.dart';
import '../../../../core/widgets/online_badge.dart';
import '../../../auth/presentation/auth_controller.dart';

class ProfileBuilderScreen extends ConsumerStatefulWidget {
  const ProfileBuilderScreen({super.key});

  @override
  ConsumerState<ProfileBuilderScreen> createState() => _ProfileBuilderScreenState();
}

class _ProfileBuilderScreenState extends ConsumerState<ProfileBuilderScreen> {
  int _currentStep = 0;
  final int _totalSteps = 6;
  final _step1FormKey = GlobalKey<FormState>();

  // Step 1: Real Account Credentials & Basic Info (All Empty by default!)
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _locationController = TextEditingController();
  final _bioController = TextEditingController();
  bool _obscurePassword = true;
  String _selectedGender = 'prefer_not_to_say';

  // Step 2: Voice Discovery Preferences
  final List<String> _preferredGenders = ['everyone'];

  // Step 3: Photos & Visuals
  String _avatarUrl = 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500&auto=format&fit=crop&q=80';
  String _coverUrl = 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=1000&auto=format&fit=crop&q=80';
  final List<String> _galleryPhotos = [];

  // Step 4: Interests & Tags (Start with empty selection)
  final List<String> _availableInterests = [
    'Music', 'Movies', 'Travelling', 'Technology', 'Gaming', 'Sports',
    'Photography', 'Food', 'Business', 'Art', 'Fitness', 'Books',
    'Nature', 'Entertainment', 'Culture', 'Learning', 'Lifestyle'
  ];
  final Set<String> _selectedInterests = {};

  // Step 5: Voice Introduction
  bool _isRecording = false;
  bool _hasVoiceIntro = false;
  bool _isPlayingIntro = false;
  final int _voiceIntroDuration = 15;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _locationController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: Text(
          'Step ${_currentStep + 1} of $_totalSteps',
          style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => setState(() => _currentStep--),
              )
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.go('/onboarding'),
              ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            backgroundColor: AppColors.cardBackground,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryAccent),
            minHeight: 3,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (authState.errorMessage != null && _currentStep == _totalSteps - 1) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.error.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                authState.errorMessage!,
                                style: const TextStyle(color: AppColors.error, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    _buildCurrentStepView(),
                  ],
                ),
              ),
            ),
            _buildBottomBar(authState),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildStep1AccountAndBasic();
      case 1:
        return _buildStep2DiscoveryPreferences();
      case 2:
        return _buildStep3Photos();
      case 3:
        return _buildStep4Interests();
      case 4:
        return _buildStep5VoiceIntro();
      case 5:
        return _buildStep6ProfilePreview();
      default:
        return const SizedBox();
    }
  }

  // STEP 1: ACCOUNT CREDENTIALS & BASIC INFO
  Widget _buildStep1AccountAndBasic() {
    return Form(
      key: _step1FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create Your Account',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter your real login credentials and voice profile details.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),

          // Email Field
          _buildValidatedField(
            label: 'Email Address *',
            controller: _emailController,
            hint: 'name@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Email is required';
              if (!val.contains('@') || !val.contains('.')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Password Field
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Password *', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(color: Colors.white),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Password is required';
                  if (val.trim().length < 6) return 'Password must be at least 6 characters';
                  return null;
                },
                decoration: InputDecoration(
                  hintText: 'Create a password (min 6 chars)',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.textMuted, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppColors.textMuted),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Username Field
          _buildValidatedField(
            label: 'Username *',
            controller: _usernameController,
            hint: 'e.g. alex24 (unique @handle)',
            icon: Icons.alternate_email_rounded,
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Username is required';
              if (val.trim().length < 3) return 'Username must be at least 3 characters';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Display Name Field
          _buildValidatedField(
            label: 'Display Name *',
            controller: _displayNameController,
            hint: 'How people see you (e.g. Alex)',
            icon: Icons.person_rounded,
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Display Name is required';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Location Field
          _buildValidatedField(
            label: 'Location (Optional)',
            controller: _locationController,
            hint: 'e.g. New York, USA',
            icon: Icons.location_on_rounded,
          ),
          const SizedBox(height: 16),

          // Short Bio Field
          _buildValidatedField(
            label: 'Short Bio (Optional)',
            controller: _bioController,
            hint: 'Tell others what you love talking about...',
            icon: Icons.edit_note_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 20),

          // Gender Selection
          const Text('Gender', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 14)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildGenderChip('male', 'Male'),
              _buildGenderChip('female', 'Female'),
              _buildGenderChip('non_binary', 'Non-Binary'),
              _buildGenderChip('prefer_not_to_say', 'Prefer Not to Say'),
              _buildGenderChip('other', 'Other'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildValidatedField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 14)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderChip(String value, String label) {
    final isSelected = _selectedGender == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedGender = value),
      selectedColor: AppColors.primaryAccent.withOpacity(0.25),
      backgroundColor: AppColors.secondaryBackground,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primaryAccentLight : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.primaryAccent : AppColors.glassBorder,
      ),
    );
  }

  // STEP 2: DISCOVERY PREFERENCES
  Widget _buildStep2DiscoveryPreferences() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Voice Discovery Preferences',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 6),
        const Text(
          'Select which genders you prefer to discover and connect with in spontaneous voice calls.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 28),

        _buildPrefOption('everyone', 'Everyone', 'Discover anyone with shared interests', Icons.public_rounded),
        const SizedBox(height: 12),
        _buildPrefOption('women', 'Women', 'Only discover women on the voice radar', Icons.female_rounded),
        const SizedBox(height: 12),
        _buildPrefOption('men', 'Men', 'Only discover men on the voice radar', Icons.male_rounded),
        const SizedBox(height: 12),
        _buildPrefOption('non_binary', 'Non-Binary', 'Discover non-binary individuals', Icons.transgender_rounded),
      ],
    );
  }

  Widget _buildPrefOption(String value, String title, String subtitle, IconData icon) {
    final isSelected = _preferredGenders.contains(value);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (value == 'everyone') {
            _preferredGenders.clear();
            _preferredGenders.add('everyone');
          } else {
            _preferredGenders.remove('everyone');
            if (isSelected) {
              _preferredGenders.remove(value);
              if (_preferredGenders.isEmpty) _preferredGenders.add('everyone');
            } else {
              _preferredGenders.add(value);
            }
          }
        });
      },
      child: GlassContainer(
        backgroundColor: isSelected ? AppColors.primaryAccent.withOpacity(0.15) : null,
        border: Border.all(
          color: isSelected ? AppColors.primaryAccent : AppColors.glassBorder,
          width: isSelected ? 1.5 : 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryAccent.withOpacity(0.2) : AppColors.secondaryBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isSelected ? AppColors.primaryAccent : AppColors.textMuted, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? AppColors.primaryAccent : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  // STEP 3: PHOTOS & APPEARANCE
  Widget _buildStep3Photos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Profile Photos',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose your profile visual style.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),

        Center(
          child: Stack(
            children: [
              CircleAvatar(
                radius: 54,
                backgroundColor: AppColors.primaryAccent,
                child: CircleAvatar(
                  radius: 50,
                  backgroundImage: NetworkImage(_avatarUrl),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        Center(
          child: TextButton.icon(
            onPressed: () {
              // Cycle through attractive avatars
              final avatars = [
                'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
                'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
                'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500',
                'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=500',
                'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=500',
              ];
              final nextIndex = (avatars.indexOf(_avatarUrl) + 1) % avatars.length;
              setState(() => _avatarUrl = avatars[nextIndex]);
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Shuffle Avatar Style'),
          ),
        ),
      ],
    );
  }

  // STEP 4: INTERESTS
  Widget _buildStep4Interests() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Your Interests',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 6),
        const Text(
          'Select at least 1 topic to discover people sharing your passions.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _availableInterests.map((interest) {
            final isSelected = _selectedInterests.contains(interest);
            return FilterChip(
              label: Text(interest),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedInterests.add(interest);
                  } else {
                    _selectedInterests.remove(interest);
                  }
                });
              },
              backgroundColor: AppColors.secondaryBackground,
              selectedColor: AppColors.primaryAccent.withOpacity(0.25),
              side: BorderSide(color: isSelected ? AppColors.primaryAccent : AppColors.glassBorder),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              showCheckmark: isSelected,
              checkmarkColor: AppColors.primaryAccent,
            );
          }).toList(),
        ),
      ],
    );
  }

  // STEP 5: VOICE INTRODUCTION
  Widget _buildStep5VoiceIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Record Voice Intro',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 6),
        const Text(
          'Introduce yourself in your own voice! Tap to record a 10–20s greeting.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 32),

        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              VoiceWaveformWidget(
                isSpeaking: _isRecording || _isPlayingIntro,
                barCount: 22,
                maxHeight: 70,
              ),
              const SizedBox(height: 20),
              Text(
                _isRecording ? 'Recording (00:08)...' : (_hasVoiceIntro ? '00:15 Voice Intro Recorded' : 'Tap mic to record intro'),
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isRecording = !_isRecording;
                        if (!_isRecording) _hasVoiceIntro = true;
                      });
                    },
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        gradient: _isRecording
                            ? const LinearGradient(colors: [Colors.redAccent, Colors.red])
                            : AppColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? Colors.red : AppColors.primaryAccent).withOpacity(0.4),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  if (_hasVoiceIntro && !_isRecording) ...[
                    const SizedBox(width: 20),
                    IconButton(
                      iconSize: 44,
                      icon: Icon(
                        _isPlayingIntro ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                        color: AppColors.secondaryAccent,
                      ),
                      onPressed: () {
                        setState(() => _isPlayingIntro = !_isPlayingIntro);
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // STEP 6: REVIEW & PUBLISH
  Widget _buildStep6ProfilePreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Confirm Your Profile',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 6),
        const Text(
          'Here is your voice discovery card. Tap "Create Account" below to register!',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),

        GlassContainer(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundImage: NetworkImage(_avatarUrl),
                      ),
                      const Positioned(
                        bottom: 0,
                        right: 0,
                        child: OnlineBadge(size: 14, isOnline: true),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayNameController.text.trim().isEmpty ? 'Your Name' : _displayNameController.text.trim(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        Text(
                          '@${_usernameController.text.trim().isEmpty ? 'username' : _usernameController.text.trim()}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        Text(
                          _emailController.text.trim(),
                          style: const TextStyle(color: AppColors.primaryAccentLight, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_bioController.text.trim().isNotEmpty) ...[
                Text(
                  _bioController.text.trim(),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _selectedInterests.map((t) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Text('#$t', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                )).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(AuthState authState) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.secondaryBackground,
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            OutlinedButton(
              onPressed: () => setState(() => _currentStep--),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.glassBorder),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Back', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: GradientButton(
              isLoading: authState.isLoading,
              text: _currentStep == _totalSteps - 1 ? 'Create Account & Enter' : 'Continue',
              onPressed: () async {
                // Validate Step 1 before proceeding
                if (_currentStep == 0) {
                  if (!(_step1FormKey.currentState?.validate() ?? false)) {
                    return;
                  }
                }

                if (_currentStep < _totalSteps - 1) {
                  setState(() => _currentStep++);
                } else {
                  // Final submission: Register user with typed real credentials!
                  final success = await ref.read(authControllerProvider.notifier).register(
                    email: _emailController.text.trim(),
                    password: _passwordController.text.trim(),
                    username: _usernameController.text.trim(),
                    displayName: _displayNameController.text.trim(),
                    gender: _selectedGender,
                    location: _locationController.text.trim(),
                    bio: _bioController.text.trim(),
                    interests: _selectedInterests.toList(),
                    voiceIntroUrl: _hasVoiceIntro ? 'https://actions.google.com/sounds/v1/speech/female_voice.ogg' : null,
                    voiceIntroDuration: _hasVoiceIntro ? _voiceIntroDuration : 0,
                  );

                  if (success && mounted) {
                    context.go('/home');
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
