import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'score_mark.dart';
import 'score_panel.dart';

class ScorecardShareCard extends StatelessWidget {
  const ScorecardShareCard({
    super.key,
    required this.courseName,
    required this.playedAt,
    required this.lines,
    required this.totalScore,
  });

  final String courseName;
  final DateTime playedAt;
  final List<HoleScoreLine> lines;
  final int totalScore;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String formatDate(DateTime date) {
    final month = _months[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  static String formatRelativeToPar(int relative) {
    if (relative == 0) return 'E';
    if (relative > 0) return '+$relative';
    return '$relative';
  }

  int get _parTotal => lines.fold<int>(0, (sum, line) => sum + line.par);

  int get _relativeToPar {
    var relative = 0;
    for (final line in lines) {
      if (line.score <= 0 || line.par <= 0) continue;
      relative += line.score - line.par;
    }
    return relative;
  }

  @override
  Widget build(BuildContext context) {
    final useGrid = lines.length == 18;

    return Container(
      width: 400,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A3328), Color(0xFF121218)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.45)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              courseName.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.accentGreen,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              formatDate(playedAt),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.accentGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.accentGreen.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SummaryStat(label: 'PAR', value: '$_parTotal'),
                  const SizedBox(width: 28),
                  _SummaryStat(label: 'SCORE', value: '$totalScore'),
                  const SizedBox(width: 28),
                  _SummaryStat(
                    label: '+/-',
                    value: formatRelativeToPar(_relativeToPar),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (useGrid)
              _EighteenHoleGrid(lines: lines)
            else
              _ScoreList(lines: lines),
            const SizedBox(height: 14),
            Text(
              'South Texas Golf Tracker',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _EighteenHoleGrid extends StatelessWidget {
  const _EighteenHoleGrid({required this.lines});

  final List<HoleScoreLine> lines;

  @override
  Widget build(BuildContext context) {
    final front = lines.sublist(0, 9);
    final back = lines.sublist(9, 18);
    final frontPar = front.fold<int>(0, (sum, line) => sum + line.par);
    final backPar = back.fold<int>(0, (sum, line) => sum + line.par);
    final frontScore = front.fold<int>(0, (sum, line) => sum + line.score);
    final backScore = back.fold<int>(0, (sum, line) => sum + line.score);

    return Column(
      children: [
        _NineHoleBlock(label: 'OUT', lines: front, subtotalPar: frontPar, subtotalScore: frontScore),
        const SizedBox(height: 12),
        _NineHoleBlock(label: 'IN', lines: back, subtotalPar: backPar, subtotalScore: backScore),
      ],
    );
  }
}

class _NineHoleBlock extends StatelessWidget {
  const _NineHoleBlock({
    required this.label,
    required this.lines,
    required this.subtotalPar,
    required this.subtotalScore,
  });

  final String label;
  final List<HoleScoreLine> lines;
  final int subtotalPar;
  final int subtotalScore;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GridRow(
          label: 'HOLE',
          values: lines.map((line) => line.hole).toList(),
          isHeader: true,
        ),
        const SizedBox(height: 4),
        _GridRow(
          label: 'PAR',
          values: lines.map((line) => line.par > 0 ? '${line.par}' : '—').toList(),
          isHeader: true,
        ),
        const SizedBox(height: 4),
        _ScoreGridRow(lines: lines),
        const SizedBox(height: 4),
        Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                label,
                style: const TextStyle(
                  color: AppTheme.accentGreen,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const Expanded(child: SizedBox()),
            SizedBox(
              width: 34,
              child: Column(
                children: [
                  Text(
                    '$subtotalPar',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$subtotalScore',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GridRow extends StatelessWidget {
  const _GridRow({
    required this.label,
    required this.values,
    this.isHeader = false,
  });

  final String label;
  final List<String> values;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.accentGreen,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
        ...values.map(
          (value) => Expanded(
            child: Center(
              child: Text(
                value,
                style: TextStyle(
                  color: isHeader
                      ? Colors.white.withValues(alpha: 0.85)
                      : Colors.white,
                  fontSize: isHeader ? 11 : 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 34),
      ],
    );
  }
}

class _ScoreGridRow extends StatelessWidget {
  const _ScoreGridRow({required this.lines});

  final List<HoleScoreLine> lines;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 34,
          child: Text(
            'SCR',
            style: TextStyle(
              color: AppTheme.accentGreen,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
        ...lines.map(
          (line) => Expanded(
            child: Center(
              child: ScoreMark(
                score: line.score,
                par: line.par,
                color: Colors.white,
                fontSize: 12,
                width: 24,
                height: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 34),
      ],
    );
  }
}

class _ScoreList extends StatelessWidget {
  const _ScoreList({required this.lines});

  final List<HoleScoreLine> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                'HOLE',
                style: TextStyle(
                  color: AppTheme.accentGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Text(
                'PAR',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.accentGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Text(
                'SCORE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.accentGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...lines.map(
          (line) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    line.hole,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    line.par > 0 ? '${line.par}' : '—',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: ScoreMark(
                      score: line.score,
                      par: line.par,
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
