import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../services/scorecard_share_service.dart';
import 'score_mark.dart';

class HoleScoreLine {
  const HoleScoreLine({
    required this.hole,
    required this.par,
    required this.score,
    this.putts = 0,
  });

  final String hole;
  final int par;
  final int score;
  final int putts;
}

class ScorePanel extends StatelessWidget {
  const ScorePanel({
    super.key,
    required this.par,
    required this.currentHoleScore,
    required this.currentHolePutts,
    required this.totalScore,
    required this.scorecardLines,
    required this.onScoreChanged,
    required this.onPuttsChanged,
    required this.courseName,
    required this.playedAt,
    this.holeRelativeToPar = 0,
    this.totalRelativeToPar = 0,
    this.strokesRemainingForEvenPar,
    this.holesToPlay,
    this.showScoreTarget = true,
    required this.scoreTargetTotal,
    required this.coursePar,
    this.onScoreTargetChanged,
  });

  final int par;
  final int currentHoleScore;
  final int currentHolePutts;
  final int totalScore;
  final List<HoleScoreLine> scorecardLines;
  final ValueChanged<int> onScoreChanged;
  final ValueChanged<int> onPuttsChanged;
  final String courseName;
  final DateTime playedAt;
  final int holeRelativeToPar;
  final int totalRelativeToPar;
  final int? strokesRemainingForEvenPar;
  final int? holesToPlay;
  final bool showScoreTarget;
  final int scoreTargetTotal;
  final int coursePar;
  final ValueChanged<int>? onScoreTargetChanged;

  static String _formatRelativeToPar(int relative) {
    if (relative == 0) return '';
    if (relative > 0) return '(+$relative)';
    return '($relative)';
  }

  void _showTargetPicker(BuildContext context) {
    if (onScoreTargetChanged == null) return;

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ScoreTargetPickerSheet(
        initialTarget: scoreTargetTotal,
        coursePar: coursePar,
        onTargetSelected: onScoreTargetChanged!,
      ),
    );
  }

  void _showScorecard(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ScorecardSheet(
        courseName: courseName,
        playedAt: playedAt,
        lines: scorecardLines,
        totalScore: totalScore,
      ),
    );
  }

  Color _scoreColor(int score) {
    if (par <= 0 || score <= 0) return Colors.white;
    if (score < par) return const Color(0xFFEF4444);
    if (score == par) return AppTheme.measureBlue;
    return Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SidebarScorePicker(
                  score: currentHoleScore,
                  par: par,
                  onScoreChanged: onScoreChanged,
                  scoreColor: _scoreColor(currentHoleScore),
                ),
                const SizedBox(width: 6),
                SidebarPuttsPicker(
                  putts: currentHolePutts,
                  onPuttsChanged: onPuttsChanged,
                ),
              ],
            ),
            if (showScoreTarget &&
                strokesRemainingForEvenPar != null &&
                holesToPlay != null) ...[
              const SizedBox(height: 4),
              _TargetSummary(
                strokesRemaining: strokesRemainingForEvenPar!,
                holesToPlay: holesToPlay!,
                onTargetTap: onScoreTargetChanged != null
                    ? () => _showTargetPicker(context)
                    : null,
              ),
            ],
            if (holeRelativeToPar != 0) ...[
              const SizedBox(height: 4),
              Text(
                _formatRelativeToPar(holeRelativeToPar),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(width: 8),
        _CompactTotalBox(
          totalScore: totalScore,
          totalRelativeToPar: totalRelativeToPar,
          formatRelative: _formatRelativeToPar,
          onTap: () => _showScorecard(context),
        ),
      ],
    );
  }
}

class SidebarScorePicker extends StatefulWidget {
  const SidebarScorePicker({
    super.key,
    required this.score,
    required this.onScoreChanged,
    this.par = 0,
    this.maxScore = 15,
    this.scoreColor,
    this.strokesRemaining,
    this.holesToPlay,
    this.targetScore,
    this.onTargetTap,
  });

  final int score;
  final int par;
  final int maxScore;
  final ValueChanged<int> onScoreChanged;
  final Color? scoreColor;
  final int? strokesRemaining;
  final int? holesToPlay;
  final int? targetScore;
  final VoidCallback? onTargetTap;

  @override
  State<SidebarScorePicker> createState() => _SidebarScorePickerState();
}

class _SidebarScorePickerState extends State<SidebarScorePicker> {
  static const _boxWidth = 52.0;
  static const _compactHeight = 72.0;
  static const _expandedHeight = 100.0;

  bool get _showTarget =>
      widget.strokesRemaining != null && widget.holesToPlay != null;

  double get _boxHeight =>
      _showTarget ? _expandedHeight : _compactHeight;

  late FixedExtentScrollController _controller;
  bool _syncing = false;

  int get _itemCount => widget.maxScore + 1;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(
      initialItem: widget.score.clamp(0, widget.maxScore),
    );
    _controller.addListener(_onWheelScroll);
  }

  @override
  void didUpdateWidget(SidebarScorePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score ||
        oldWidget.maxScore != widget.maxScore) {
      _jumpToScore();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onWheelScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onWheelScroll() {
    if (mounted) setState(() {});
  }

  void _jumpToScore() {
    final index = widget.score.clamp(0, widget.maxScore);
    if (_controller.selectedItem == index) return;
    _syncing = true;
    _controller.jumpToItem(index);
    _syncing = false;
  }

  void _onWheelChanged(int index) {
    if (_syncing) return;
    final score = index.clamp(0, widget.maxScore);
    if (score == widget.score) return;
    HapticFeedback.selectionClick();
    widget.onScoreChanged(score);
  }

  Color _itemColor(int index, bool isCentered) {
    if (!isCentered) {
      return AppTheme.textMuted.withValues(alpha: 0.5);
    }
    if (widget.scoreColor != null && index == widget.score) {
      return widget.scoreColor!;
    }
    if (widget.par <= 0 || index <= 0) return Colors.white;
    if (index < widget.par) return const Color(0xFFEF4444);
    if (index == widget.par) return AppTheme.measureBlue;
    return Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    Widget? buildTargetSection() {
      if (!_showTarget) return null;

      final content = Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'LEFT ${widget.strokesRemaining}',
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  height: 1.1,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'FOR ${widget.holesToPlay} TO PLAY',
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      );

      if (widget.onTargetTap == null) return content;

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTargetTap,
          child: content,
        ),
      );
    }

    final targetSection = buildTargetSection();

    return Container(
      width: _boxWidth,
      height: _boxHeight,
      decoration: BoxDecoration(
        color: AppTheme.accentGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGreenDim),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'HOLE SCORE',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          Expanded(
            child: Listener(
              onPointerDown: (_) => HapticFeedback.lightImpact(),
              child: ListWheelScrollView.useDelegate(
                controller: _controller,
                itemExtent: 22,
                diameterRatio: 1.35,
                perspective: 0.004,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: _onWheelChanged,
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: _itemCount,
                  builder: (context, index) {
                    final isCentered = index == _controller.selectedItem;
                    final color = _itemColor(index, isCentered);
                    return Center(
                      child: ScoreMark(
                        score: index,
                        par: widget.par,
                        color: color,
                        fontSize: isCentered ? 20 : 13,
                        width: isCentered ? 32 : 24,
                        height: isCentered ? 22 : 18,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          if (targetSection != null) targetSection,
        ],
      ),
    );
  }
}

class SidebarPuttsPicker extends StatefulWidget {
  const SidebarPuttsPicker({
    super.key,
    required this.putts,
    required this.onPuttsChanged,
    this.maxPutts = 9,
  });

  final int putts;
  final int maxPutts;
  final ValueChanged<int> onPuttsChanged;

  @override
  State<SidebarPuttsPicker> createState() => _SidebarPuttsPickerState();
}

class _SidebarPuttsPickerState extends State<SidebarPuttsPicker> {
  static const _boxWidth = 52.0;
  static const _boxHeight = 72.0;

  late FixedExtentScrollController _controller;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(
      initialItem: widget.putts.clamp(0, widget.maxPutts),
    );
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(SidebarPuttsPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.putts != widget.putts ||
        oldWidget.maxPutts != widget.maxPutts) {
      final index = widget.putts.clamp(0, widget.maxPutts);
      if (_controller.selectedItem != index) {
        _syncing = true;
        _controller.jumpToItem(index);
        _syncing = false;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onWheelChanged(int index) {
    if (_syncing) return;
    final putts = index.clamp(0, widget.maxPutts);
    if (putts == widget.putts) return;
    HapticFeedback.selectionClick();
    widget.onPuttsChanged(putts);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _boxWidth,
      height: _boxHeight,
      decoration: BoxDecoration(
        color: AppTheme.accentGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGreenDim),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 2, right: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'PUTTS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          Expanded(
            child: Listener(
              onPointerDown: (_) => HapticFeedback.lightImpact(),
              child: ListWheelScrollView.useDelegate(
                controller: _controller,
                itemExtent: 22,
                diameterRatio: 1.35,
                perspective: 0.004,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: _onWheelChanged,
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: widget.maxPutts + 1,
                  builder: (context, index) {
                    final isCentered = index == _controller.selectedItem;
                    return Center(
                      child: Text(
                        index == 0 ? '—' : '$index',
                        style: TextStyle(
                          color: isCentered
                              ? Colors.white
                              : AppTheme.textMuted.withValues(alpha: 0.5),
                          fontSize: isCentered ? 20 : 13,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetSummary extends StatelessWidget {
  const _TargetSummary({
    required this.strokesRemaining,
    required this.holesToPlay,
    this.onTargetTap,
  });

  final int strokesRemaining;
  final int holesToPlay;
  final VoidCallback? onTargetTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'LEFT $strokesRemaining',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        Text(
          'FOR $holesToPlay TO PLAY',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ],
    );

    if (onTargetTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTargetTap,
        child: content,
      ),
    );
  }
}

class _CompactTotalBox extends StatelessWidget {
  const _CompactTotalBox({
    required this.totalScore,
    required this.totalRelativeToPar,
    required this.formatRelative,
    required this.onTap,
  });

  final int totalScore;
  final int totalRelativeToPar;
  final String Function(int) formatRelative;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.accentGreen,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 52,
          height: 72,
          decoration: BoxDecoration(
            color: AppTheme.accentGreen,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.accentGreenDim),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'TOT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$totalScore',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              if (totalRelativeToPar != 0) ...[
                const SizedBox(height: 2),
                Text(
                  formatRelative(totalRelativeToPar),
                  style: TextStyle(
                    color: totalRelativeToPar < 0
                        ? const Color(0xFFEF4444)
                        : Colors.white.withValues(alpha: 0.9),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScorecardSheet extends StatefulWidget {
  const _ScorecardSheet({
    required this.courseName,
    required this.playedAt,
    required this.lines,
    required this.totalScore,
  });

  final String courseName;
  final DateTime playedAt;
  final List<HoleScoreLine> lines;
  final int totalScore;

  @override
  State<_ScorecardSheet> createState() => _ScorecardSheetState();
}

class _ScorecardSheetState extends State<_ScorecardSheet> {
  final _shareService = ScorecardShareService();
  bool _sharing = false;

  Future<void> _shareScorecard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await _shareService.shareScorecard(
        context: context,
        courseName: widget.courseName,
        playedAt: widget.playedAt,
        lines: widget.lines,
        totalScore: widget.totalScore,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share scorecard: $error')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    final totalScore = widget.totalScore;
    final parTotal = lines.fold<int>(0, (sum, line) => sum + line.par);
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.55;

    return SizedBox(
      height: sheetHeight,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
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
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Scorecard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Material(
                    color: AppTheme.accentGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: _sharing ? null : _shareScorecard,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_sharing)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.accentGreen,
                                ),
                              )
                            else
                              const Icon(
                                Icons.ios_share_rounded,
                                size: 16,
                                color: AppTheme.accentGreen,
                              ),
                            const SizedBox(width: 6),
                            const Text(
                              'Share',
                              style: TextStyle(
                                color: AppTheme.accentGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _ScorecardHeaderRow(),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: lines.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final line = lines[index];
                    return _ScorecardDataRow(
                      hole: line.hole,
                      par: line.par,
                      score: line.score,
                      putts: line.putts,
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
            'Putts',
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
    this.putts = 0,
    this.emphasized = false,
  });

  final String hole;
  final int par;
  final int score;
  final int putts;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasized
            ? AppTheme.accentGreen.withValues(alpha: 0.12)
            : const Color(0xFF1A1A22),
        borderRadius: BorderRadius.circular(12),
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
              putts > 0 ? '$putts' : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: emphasized ? Colors.white : AppTheme.textMuted,
                fontSize: emphasized ? 14 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: emphasized
                  ? Text(
                      '$score',
                      style: TextStyle(
                        color: AppTheme.accentGreen,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : ScoreMark(
                      score: score,
                      par: par,
                      color: Colors.white,
                      fontSize: 13,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreTargetPickerSheet extends StatefulWidget {
  const _ScoreTargetPickerSheet({
    required this.initialTarget,
    required this.coursePar,
    required this.onTargetSelected,
  });

  final int initialTarget;
  final int coursePar;
  final ValueChanged<int> onTargetSelected;

  @override
  State<_ScoreTargetPickerSheet> createState() =>
      _ScoreTargetPickerSheetState();
}

class _ScoreTargetPickerSheetState extends State<_ScoreTargetPickerSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialTarget}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyTarget(int value) {
    if (value <= 0) return;
    widget.onTargetSelected(value);
    Navigator.pop(context);
  }

  void _applyFromField() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value <= 0) return;
    _applyTarget(value);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
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
              'Score Target',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                hintText: 'Target score',
                hintStyle: TextStyle(
                  color: AppTheme.textMuted.withValues(alpha: 0.8),
                ),
                filled: true,
                fillColor: const Color(0xFF1A1A22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.panelBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.panelBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.accentGreen),
                ),
              ),
              onSubmitted: (_) => _applyFromField(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _TargetPresetChip(
                  label: 'Par (${widget.coursePar})',
                  onTap: () => _applyTarget(widget.coursePar),
                ),
                _TargetPresetChip(
                  label: '80',
                  onTap: () => _applyTarget(80),
                ),
                _TargetPresetChip(
                  label: '90',
                  onTap: () => _applyTarget(90),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: AppTheme.accentGreen,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _applyFromField,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Set Target',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetPresetChip extends StatelessWidget {
  const _TargetPresetChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A22),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.panelBorder),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
