import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/saved_round.dart';
import '../services/golf_data_service.dart';
import '../services/round_storage_service.dart';
import 'golf_map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _dataService = GolfDataService();
  final _roundStorage = RoundStorageService();

  List<String> _courses = [];
  List<SavedRound> _savedRounds = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final features = await _dataService.fetchGolfFeatures();
      final courses = _dataService.extractCourses(features);
      final rounds = await _roundStorage.loadRounds();

      if (!mounted) return;
      setState(() {
        _courses = courses;
        _savedRounds = rounds;
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

  Future<void> _startRound(String course) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GolfMapScreen(initialCourse: course),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openRound(SavedRound round) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GolfMapScreen(
          initialCourse: round.courseName,
          initialScores: round.scores,
          initialPinnedShots: round.pinnedShots,
          existingRoundId: round.id,
          existingRoundPlayedAt: round.playedAt,
        ),
      ),
    );
    if (saved == true) _load();
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
            'Golf Map',
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
          const _SectionTitle(title: 'Start a round'),
          const SizedBox(height: 10),
          if (_courses.isEmpty)
            const _EmptyCard(message: 'No courses available.')
          else
            ..._courses.map(
              (course) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CourseCard(
                  course: course,
                  onTap: () => _startRound(course),
                ),
              ),
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

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.onTap});

  final String course;
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.panelBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.golf_course_rounded,
                  color: AppTheme.accentGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  course,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppTheme.textMuted,
                size: 16,
              ),
            ],
          ),
        ),
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
