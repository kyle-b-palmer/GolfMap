import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/course_catalog.dart';
import '../models/saved_round.dart';
import '../services/app_preferences_service.dart';
import '../services/course_favorites_service.dart';
import '../services/course_visit_service.dart';
import '../services/golf_data_service.dart';
import '../services/health_workout_service.dart';
import '../services/round_live_activity_service.dart';
import '../services/round_storage_service.dart';
import '../widgets/course_catalog_list.dart';
import 'club_bag_screen.dart';
import 'golf_map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _dataService = GolfDataService();
  final _roundStorage = RoundStorageService();
  final _courseVisits = CourseVisitService();
  final _courseFavorites = CourseFavoritesService();
  final _appPrefs = AppPreferencesService();

  List<CourseCatalogEntry> _courseCatalog = [];
  List<CommonlyVisitedEntry> _commonlyVisited = [];
  List<String> _favoriteCourses = [];
  List<SavedRound> _savedRounds = [];
  bool _loading = true;
  String? _error;
  bool _startHealthWorkoutWithRound = true;
  bool _healthWorkoutAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_clearStaleLiveActivity());
    });
    _load();
  }

  Future<void> _clearStaleLiveActivity() async {
    try {
      await RoundLiveActivityService.instance.init();
      await RoundLiveActivityService.instance.end();
    } catch (_) {
      // Live Activity cleanup is best-effort; don't take down app launch.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final features = await _dataService.fetchGolfFeatures();
      final catalog = _dataService.buildCourseCatalog(features);
      final rounds = await _roundStorage.loadRounds();
      final commonlyVisited =
          await _courseVisits.commonlyVisited(savedRounds: rounds);
      final favorites = await _courseFavorites.loadFavorites();
      var startHealthWorkoutWithRound = true;
      var healthWorkoutAvailable = false;
      if (!kIsWeb && Platform.isIOS) {
        startHealthWorkoutWithRound = await _appPrefs.getStartHealthWorkoutWithRound();
        healthWorkoutAvailable = await HealthWorkoutService.instance.isAvailable();
      }

      if (!mounted) return;
      setState(() {
        _courseCatalog = catalog;
        _commonlyVisited = commonlyVisited;
        _favoriteCourses = favorites;
        _savedRounds = rounds;
        _startHealthWorkoutWithRound = startHealthWorkoutWithRound;
        _healthWorkoutAvailable = healthWorkoutAvailable;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleFavorite(String course) async {
    final result = await _courseFavorites.toggle(course);
    if (!mounted) return;

    switch (result) {
      case FavoriteToggleResult.added:
      case FavoriteToggleResult.removed:
        final favorites = await _courseFavorites.loadFavorites();
        if (!mounted) return;
        setState(() => _favoriteCourses = favorites);
      case FavoriteToggleResult.limitReached:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You can pin up to ${CourseFavoritesService.maxFavorites} courses. '
              'Unstar one to add another.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _openClubBag() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClubBagScreen()),
    );
  }

  Future<void> _startRound(String course) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.panelBorder),
        ),
        title: const Text(
          'Starting new round',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'You\'re about to start a new round at $course. Continue?',
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 14,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Continue',
              style: TextStyle(
                color: AppTheme.accentGreen,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GolfMapScreen(
          initialCourse: course,
          startHealthWorkout:
              !kIsWeb && Platform.isIOS ? _startHealthWorkoutWithRound : null,
        ),
      ),
    );
    await RoundLiveActivityService.instance.end();
    if (mounted) _load();
  }

  Future<void> _setStartHealthWorkoutWithRound(bool value) async {
    setState(() => _startHealthWorkoutWithRound = value);
    await _appPrefs.setStartHealthWorkoutWithRound(value);
  }

  Future<void> _openRound(SavedRound round) async {
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GolfMapScreen(
          initialCourse: round.courseName,
          initialScores: round.scores,
          initialPutts: round.putts,
          initialPinnedShots: round.pinnedShots,
          initialMeasurementChains: round.measurementChains,
          initialLockedHoles: round.lockedHoles,
          existingRoundId: round.id,
          existingRoundPlayedAt: round.playedAt,
        ),
      ),
    );
    await RoundLiveActivityService.instance.end();
    if (mounted) _load();
  }

  Future<void> _deleteRound(SavedRound round) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: const Text('Delete round?'),
        content: Text(
          'Remove ${round.courseName} from ${_formatDate(round.playedAt)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _roundStorage.deleteRound(round.id);
    _load();
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0E),
      body: kIsWeb
          ? _buildBody()
          : SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentGreen),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 40),
              const SizedBox(height: 12),
              Text(
                'Could not load courses',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accentGreen,
                  foregroundColor: const Color(0xFF0F172A),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.accentGreen,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          const Text(
            'South Texas Golf Tracker',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pick a course to play or review past rounds.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 28),
          if (_favoriteCourses.isNotEmpty) ...[
            const _SectionTitle(title: 'Favorites'),
            const SizedBox(height: 10),
            FavoritesSection(
              favoriteCourses: _favoriteCourses,
              catalog: _courseCatalog,
              onSelectCourse: _startRound,
              onToggleFavorite: _toggleFavorite,
            ),
          ],
          if (_commonlyVisited.isNotEmpty) ...[
            const _SectionTitle(title: 'Commonly visited'),
            const SizedBox(height: 10),
            CommonlyVisitedSection(
              entries: _commonlyVisited,
              catalog: _courseCatalog,
              favoriteCourses: _favoriteCourses.toSet(),
              onSelectCourse: _startRound,
              onToggleFavorite: _toggleFavorite,
            ),
          ],
          _HomeActionCard(
            icon: Icons.golf_course_rounded,
            title: 'My club bag',
            subtitle: 'Set carry distances for club suggestions on the course',
            onTap: _openClubBag,
          ),
          if (!kIsWeb && Platform.isIOS && _healthWorkoutAvailable) ...[
            const SizedBox(height: 12),
            _HealthWorkoutRoundToggle(
              value: _startHealthWorkoutWithRound,
              onChanged: _setStartHealthWorkoutWithRound,
            ),
          ],
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Start a round'),
          const SizedBox(height: 10),
          CourseCatalogList(
            entries: _courseCatalog,
            favoriteCourses: _favoriteCourses.toSet(),
            onSelectCourse: _startRound,
            onToggleFavorite: _toggleFavorite,
          ),
          const SizedBox(height: 28),
          const _SectionTitle(title: 'Saved rounds'),
          const SizedBox(height: 10),
          if (_savedRounds.isEmpty)
            const _EmptyCard(
              message: 'No saved rounds yet. Play a round and tap Save on the map.',
            )
          else
            ..._savedRounds.map(
              (round) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SavedRoundCard(
                  round: round,
                  dateLabel: _formatDate(round.playedAt),
                  onTap: () => _openRound(round),
                  onDelete: () => _deleteRound(round),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HealthWorkoutRoundToggle extends StatelessWidget {
  const _HealthWorkoutRoundToggle({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.panelBg,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.panelBorder),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.favorite_rounded,
              color: Color(0xFFFF5252),
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Apple Health workout',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value
                        ? 'Track this round as a golf workout in Apple Health'
                        : 'Workout tracking off for new rounds',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: AppTheme.accentGreen,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.panelBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.panelBorder),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.accentGreen, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: AppTheme.accentGreen,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.panelBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
      ),
    );
  }
}

class _SavedRoundCard extends StatelessWidget {
  const _SavedRoundCard({
    required this.round,
    required this.dateLabel,
    required this.onTap,
    required this.onDelete,
  });

  final SavedRound round;
  final String dateLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.panelBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.panelBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      round.courseName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${round.totalStrokes}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${round.holesScored}/${round.scores.length} holes',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  if (round.totalPinnedShots > 0)
                    Text(
                      '${round.totalPinnedShots} pinned shots',
                      style: const TextStyle(
                        color: Color(0xFFFF9800),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.textMuted,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
