import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class HoleScoreLine {
  const HoleScoreLine({
    required this.hole,
    required this.par,
    required this.score,
  });

  final String hole;
  final int par;
  final int score;
}

class ScorePanel extends StatelessWidget {
  const ScorePanel({
    super.key,
    required this.selectedHole,
    required this.par,
    required this.currentHoleScore,
    required this.totalScore,
    required this.scorecardLines,
    required this.onDecrement,
    required this.onIncrement,
    this.holeRelativeToPar = 0,
    this.totalRelativeToPar = 0,
  });

  final String selectedHole;
  final int par;
  final int currentHoleScore;
  final int totalScore;
  final List<HoleScoreLine> scorecardLines;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final int holeRelativeToPar;
  final int totalRelativeToPar;

  static String _formatRelativeToPar(int relative) {
    if (relative == 0) return '';
    if (relative > 0) return '(+$relative)';
    return '($relative)';
  }

  void _showScorecard(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ScorecardSheet(
        lines: scorecardLines,
        totalScore: totalScore,
      ),
    );
  }

  Color _scoreColor() {
    if (par <= 0 || currentHoleScore <= 0) return Colors.white;
    if (currentHoleScore < par) return const Color(0xFFEF4444);
    if (currentHoleScore == par) return AppTheme.measureBlue;
    return Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: BoxDecoration(
                color: AppTheme.panelBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.panelBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    par > 0
                        ? 'Hole $selectedHole (Par $par)'
                        : 'Hole $selectedHole',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _ScoreButton(
                        onPressed: onDecrement,
                        label: '−',
                        variant: _ScoreButtonVariant.muted,
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Score:',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 2,
                                  ),
                                  decoration: currentHoleScore > par &&
                                          par > 0
                                      ? BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        )
                                      : null,
                                  child: Text(
                                    '$currentHoleScore',
                                    style: TextStyle(
                                      color: _scoreColor(),
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                ),
                                if (holeRelativeToPar != 0) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatRelativeToPar(holeRelativeToPar),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      _ScoreButton(
                        onPressed: onIncrement,
                        label: '+',
                        variant: _ScoreButtonVariant.accent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Material(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () => _showScorecard(context),
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.accentGreen, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'TOTAL',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$totalScore',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      if (totalRelativeToPar != 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatRelativeToPar(totalRelativeToPar),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: totalRelativeToPar > 0
                                ? const Color(0xFF64748B)
                                : const Color(0xFFEF4444),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ],
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

class _ScorecardSheet extends StatelessWidget {
  const _ScorecardSheet({
    required this.lines,
    required this.totalScore,
  });

  final List<HoleScoreLine> lines;
  final int totalScore;

  @override
  Widget build(BuildContext context) {
    final parTotal = lines.fold<int>(0, (sum, line) => sum + line.par);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.55;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.panelBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Scorecard',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            const _ScorecardHeaderRow(),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: lines.length,
                separatorBuilder: (_, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final line = lines[index];
                  return _ScorecardDataRow(
                    hole: line.hole,
                    par: line.par,
                    score: line.score,
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(color: AppTheme.panelBorder, height: 1),
            ),
            _ScorecardDataRow(
              hole: 'Total',
              par: parTotal,
              score: totalScore,
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScorecardHeaderRow extends StatelessWidget {
  const _ScorecardHeaderRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            'Hole',
            style: TextStyle(
              color: AppTheme.accentGreen,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Expanded(
          child: Text(
            'Par',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.accentGreen,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Expanded(
          child: Text(
            'Score',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.accentGreen,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScorecardDataRow extends StatelessWidget {
  const _ScorecardDataRow({
    required this.hole,
    required this.par,
    required this.score,
    this.emphasized = false,
  });

  final String hole;
  final int par;
  final int score;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasized
            ? AppTheme.accentGreen.withValues(alpha: 0.12)
            : const Color(0xFF1A1A22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: emphasized ? AppTheme.accentGreen : AppTheme.panelBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              hole,
              style: TextStyle(
                color: Colors.white,
                fontSize: emphasized ? 14 : 13,
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              par > 0 ? '$par' : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: emphasized ? Colors.white : AppTheme.textMuted,
                fontSize: emphasized ? 14 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$score',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: emphasized ? AppTheme.accentGreen : Colors.white,
                fontSize: emphasized ? 14 : 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ScoreButtonVariant { accent, muted }

class _ScoreButton extends StatelessWidget {
  const _ScoreButton({
    required this.onPressed,
    required this.label,
    this.variant = _ScoreButtonVariant.accent,
  });

  final VoidCallback onPressed;
  final String label;
  final _ScoreButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final isAccent = variant == _ScoreButtonVariant.accent;
    return Material(
      color: isAccent ? AppTheme.accentGreen : const Color(0xFF2A2A32),
      shape: const CircleBorder(),
      elevation: isAccent ? 2 : 0,
      shadowColor: AppTheme.accentGreen.withValues(alpha: 0.4),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isAccent ? const Color(0xFF0F172A) : Colors.white,
                fontSize: label == '+/−' ? 11 : 18,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
