import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/saved_round.dart';
import 'score_panel.dart';
import 'scorecard_share_card.dart';

class RoundRecapShareCard extends StatelessWidget {
  const RoundRecapShareCard({
    super.key,
    required this.round,
    required this.lines,
    required this.totalScore,
    required this.relativeToPar,
    this.longestDriveYards,
    this.bestHoleLabel,
  });

  final SavedRound round;
  final List<HoleScoreLine> lines;
  final int totalScore;
  final int relativeToPar;
  final int? longestDriveYards;
  final String? bestHoleLabel;

  @override
  Widget build(BuildContext context) {
    final pinCount = round.pinnedShots.values.fold<int>(
      0,
      (sum, shots) => sum + shots.length,
    );
    final dateLabel = ScorecardShareCard.formatDate(round.playedAt);
    final relativeLabel = ScorecardShareCard.formatRelativeToPar(relativeToPar);

    return Container(
      width: 360,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12141A), Color(0xFF1C2420)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            round.courseName.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.accentGreen,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateLabel,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatChip(label: 'SCORE', value: '$totalScore'),
              const SizedBox(width: 10),
              _StatChip(label: 'VS PAR', value: relativeLabel),
              const SizedBox(width: 10),
              _StatChip(label: 'PINS', value: '$pinCount'),
            ],
          ),
          if (longestDriveYards != null || bestHoleLabel != null) ...[
            const SizedBox(height: 12),
            if (longestDriveYards != null)
              Text(
                'Longest drive: $longestDriveYards yds',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            if (bestHoleLabel != null)
              Text(
                'Best hole: $bestHoleLabel',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
          ],
          const SizedBox(height: 16),
          Text(
            'Scorecard',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final line in lines)
                if (line.score > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${line.hole}: ${line.score}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'South Texas Golf Tracker',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 9),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
