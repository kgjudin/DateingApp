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

  // Step 1: Basic Info
  final _displayNameController = TextEditingController(text: 'Alex Rivers');
  final _usernameController = TextEditingController(text: 'alex_rivers');
  final _bioController = TextEditingController(text: 'Late-night thinker, vinyl seeker, and sound explorer. Let\'s talk about good stories and music.');
  final _locationController = TextEditingController(text: 'New York, USA');
  String _selectedGender = 'male';

  // Step 2: Voice Discovery Preferences
  final List<String> _preferredGenders = ['everyone'];

  // Step 3: Photos & Visuals
  String _avatarUrl = 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500&auto=format&fit=crop&q=80';
  String _coverUrl = 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=1000&auto=format&fit=crop&q=80';
  final List<String> _galleryPhotos = [
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500&auto=format&fit=crop&q=80',
  ];

  // Step 4: Interests & Tags
  final List<String> _availableInterests = [
    'Music', 'Movies', 'Travelling', 'Technology', 'Gaming', 'Sports',
    'Photography', 'Food', 'Business', 'Art', 'Fitness', 'Books',
    'Nature', 'Entertainment', 'Culture', 'Learning', 'Lifestyle'
  ];
  final Set<String> _selectedInterests = {'Music', 'Travelling', 'Art', 'Technology'};

  // Step 5: Voice Introduction
  bool _isRecording = false;
  bool _hasVoiceIntro = true;
  bool _isPlayingIntro = false;
  int _voiceIntroDuration = 15;

  // Step 6: Topics & Conversation Starters
  final List<String> _conversationStarters = [
    'What song feels like home to you?',
    'If you could live anywhere for 3 months, where?',
    'What is the weirdest rabbit hole you went down recently?',
  ];

  @override
  Widget build(BuildContext context) {
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
                child: _buildCurrentStepView(),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildStep1BasicInfo();
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

  // STEP 1: BASIC INFO
  Widget _buildStep1BasicInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Voice Identity',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 6),
        const Text(
          'Introduce yourself to the VYBE community.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),

        _buildTextField('Display Name', _displayNameController, 'How people will know you', Icons.person_rounded),
        const SizedBox(height: 16),
        _buildTextField('Username', _usernameController, 'Unique @handle', Icons.alternate_email_rounded),
        const SizedBox(height: 16),
        _buildTextField('Location', _locationController, 'City, Country', Icons.location_on_rounded),
        const SizedBox(height: 16),
        _buildTextField('Short Bio', _bioController, 'What gives you energy?', Icons.edit_note_rounded, maxLines: 3),
        const SizedBox(height: 20),

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

        const SizedBox(height: 28),
        GlassContainer(
          padding: const EdgeInsets.all(14),
          child: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.primaryAccent, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your discovery preferences are private and can be adjusted at any time in settings.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
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
          'Profile Appearance',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 6),
        const Text(
          'Add high quality profile and cover photos to make your card stand out.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),

        // Cover & Avatar Stack Preview
        Container(
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            image: DecorationImage(
              image: NetworkImage(_coverUrl),
              fit: BoxFit.cover,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [Colors.black.withOpacity(0.2), Colors.black.withOpacity(0.7)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 16,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppColors.primaryAccent,
                      child: CircleAvatar(
                        radius: 34,
                        backgroundImage: NetworkImage(_avatarUrl),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Demo avatar switcher
                        setState(() {
                          _avatarUrl = 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500&auto=format&fit=crop&q=80';
                        });
                      },
                      icon: const Icon(Icons.cached_rounded, size: 16),
                      label: const Text('Change Avatar', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondaryBackground.withOpacity(0.85),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),
        const Text('Photo Gallery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        Row(
          children: [
            ..._galleryPhotos.map((url) => Container(
              width: 80,
              height: 80,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
                border: Border.all(color: AppColors.glassBorder),
              ),
            )),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.secondaryBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.glassBorder, style: BorderStyle.solid),
              ),
              child: const Icon(Icons.add_photo_alternate_rounded, color: AppColors.primaryAccent),
            ),
          ],
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
          'What Sparks Your Interest?',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 6),
        const Text(
          'Select at least 3 topics to discover people who love talking about the same things.',
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
          'A 10–20 second voice intro lets potential connections hear your energy, laughter, and tone.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 32),

        // Audio Recorder Card
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              VoiceWaveformWidget(
                isSpeaking: _isRecording || _isPlayingIntro,
                barCount: 22,
                maxHeight: 70,
              ),
              const SizedBox(height: 24),
              Text(
                _isRecording ? '00:08 / 00:20 (Recording...)' : '00:14 Preview Audio',
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                '"Hey! I love music, travelling, late-night conversations and meeting interesting people."',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontStyle: FontStyle.italic, fontSize: 13),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isRecording = !_isRecording;
                        if (_isRecording) _isPlayingIntro = false;
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

  // STEP 6: PREVIEW
  Widget _buildStep6ProfilePreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Profile Preview',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 6),
        const Text(
          'Here is how you appear to others on the VYBE discovery radar.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),

        // Live Discovery Card Preview
        GlassContainer(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: Image.network(
                      _coverUrl,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 16,
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: AppColors.primaryAccent,
                              child: CircleAvatar(
                                radius: 34,
                                backgroundImage: NetworkImage(_avatarUrl),
                              ),
                            ),
                            const Positioned(
                              bottom: 2,
                              right: 2,
                              child: OnlineBadge(size: 14, isOnline: true),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayNameController.text,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                            ),
                            Text(
                              '@${_usernameController.text}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _bioController.text,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 14),

                    // Voice intro preview bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primaryAccent.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.volume_up_rounded, color: AppColors.primaryAccent, size: 18),
                          SizedBox(width: 8),
                          Text('Voice Intro • 14s', style: TextStyle(color: AppColors.primaryAccentLight, fontWeight: FontWeight.w700, fontSize: 12)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedInterests.map((interest) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryBackground,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Text(
                            '#$interest',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint, IconData icon, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
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
              text: _currentStep == _totalSteps - 1 ? 'Publish & Enter VYBE' : 'Continue',
              onPressed: () async {
                if (_currentStep < _totalSteps - 1) {
                  setState(() => _currentStep++);
                } else {
                  // Finalize profile creation and navigate to Home!
                  await ref.read(authControllerProvider.notifier).register(
                        username: _usernameController.text.trim(),
                        email: '${_usernameController.text.trim()}@vybe.app',
                        password: 'password123',
                        displayName: _displayNameController.text.trim(),
                        gender: _selectedGender,
                      );
                  if (mounted) context.go('/home');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
