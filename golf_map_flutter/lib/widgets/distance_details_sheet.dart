import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import '../models/health_workout_mode.dart';
import '../utils/geo_utils.dart';
import 'distance_card.dart';

enum _DistanceTab { yardage, bunkers }

class DistanceDetailsSheet extends StatefulWidget {
  const DistanceDetailsSheet({
    super.key,
    required this.courseName,
    required this.selectedHole,
    required this.par,
    this.distanceInfo,
    required this.teeOptions,
    required this.selectedTeeFeatureId,
    required this.onSelectTee,
    required this.onPinShot,
    this.pinnedShotCount = 0,
    this.selectedMeasurementPinIndex,
    this.onSelectMeasurementPin,
    this.onDeleteSelectedPin,
    this.showScoreTarget = true,
    this.onShowScoreTargetChanged,
    this.healthWorkoutMode,
    this.onHealthWorkoutModeChanged,
  });

  final String courseName;
  final String selectedHole;
  final int par;
  final DistanceInfo? distanceInfo;
  final List<TeeOption> teeOptions;
  final dynamic selectedTeeFeatureId;
  final ValueChanged<dynamic> onSelectTee;
  final VoidCallback onPinShot;
  final int pinnedShotCount;
  final int? selectedMeasurementPinIndex;
  final ValueChanged<int>? onSelectMeasurementPin;
  final VoidCallback? onDeleteSelectedPin;
  final bool showScoreTarget;
  final ValueChanged<bool>? onShowScoreTargetChanged;
  final HealthWorkoutMode? healthWorkoutMode;
  final ValueChanged<HealthWorkoutMode>? onHealthWorkoutModeChanged;

  static Future<void> show(
    BuildContext context, {
    required String courseName,
    required String selectedHole,
    required int par,
    DistanceInfo? distanceInfo,
    required List<TeeOption> teeOptions,
    required dynamic selectedTeeFeatureId,
    required ValueChanged<dynamic> onSelectTee,
    required VoidCallback onPinShot,
    int pinnedShotCount = 0,
    int? selectedMeasurementPinIndex,
    ValueChanged<int>? onSelectMeasurementPin,
    VoidCallback? onDeleteSelectedPin,
    bool showScoreTarget = true,
    ValueChanged<bool>? onShowScoreTargetChanged,
    HealthWorkoutMode? healthWorkoutMode,
    ValueChanged<HealthWorkoutMode>? onHealthWorkoutModeChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom,
        ),
        child: DistanceDetailsSheet(
          courseName: courseName,
          selectedHole: selectedHole,
          par: par,
          distanceInfo: distanceInfo,
          teeOptions: teeOptions,
          selectedTeeFeatureId: selectedTeeFeatureId,
          onSelectTee: onSelectTee,
          onPinShot: onPinShot,
          pinnedShotCount: pinnedShotCount,
          selectedMeasurementPinIndex: selectedMeasurementPinIndex,
          onSelectMeasurementPin: onSelectMeasurementPin,
          onDeleteSelectedPin: onDeleteSelectedPin,
          showScoreTarget: showScoreTarget,
          onShowScoreTargetChanged: onShowScoreTargetChanged,
          healthWorkoutMode: healthWorkoutMode,
          onHealthWorkoutModeChanged: onHealthWorkoutModeChanged,
        ),
      ),
    );
  }

  @override
  State<DistanceDetailsSheet> createState() => _DistanceDetailsSheetState();
}

class _DistanceDetailsSheetState extends State<DistanceDetailsSheet> {
  _DistanceTab _tab = _DistanceTab.yardage;
  late bool _showScoreTarget;
  late HealthWorkoutMode _healthWorkoutMode;

  @override
  void initState() {
    super.initState();
    _showScoreTarget = widget.showScoreTarget;
    _healthWorkoutMode =
        widget.healthWorkoutMode ?? HealthWorkoutMode.always;
  }

  @override
  void didUpdateWidget(covariant DistanceDetailsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showScoreTarget != widget.showScoreTarget) {
      _showScoreTarget = widget.showScoreTarget;
    }
    if (oldWidget.healthWorkoutMode != widget.healthWorkoutMode &&
        widget.healthWorkoutMode != null) {
      _healthWorkoutMode = widget.healthWorkoutMode!;
    }
  }

  void _onScoreTargetToggled(bool value) {
    setState(() => _showScoreTarget = value);
    widget.onShowScoreTargetChanged?.call(value);
  }

  void _onHealthWorkoutModeSelected(HealthWorkoutMode mode) {
    setState(() => _healthWorkoutMode = mode);
    widget.onHealthWorkoutModeChanged?.call(mode);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.distanceInfo;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.panelBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.courseName.toUpperCase(),
              style: TextStyle(
                color: AppTheme.accentGreen,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.par > 0
                  ? 'Hole ${widget.selectedHole} · Par ${widget.par}'
                  : 'Hole ${widget.selectedHole}',
              style: const TextStyle(
                color: Color(0xFFE8EAED),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SheetTabChip(
                    label: 'Yardage',
                    selected: _tab == _DistanceTab.yardage,
                    onTap: () => setState(() => _tab = _DistanceTab.yardage),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SheetTabChip(
                    label: 'Bunkers',
                    selected: _tab == _DistanceTab.bunkers,
                    onTap: () => setState(() => _tab = _DistanceTab.bunkers),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.onShowScoreTargetChanged != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.panelBorder),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Score target',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    _showScoreTarget
                        ? 'Show LEFT / FOR X TO PLAY in score box'
                        : 'Show score total only',
                    style: TextStyle(
                      color: AppTheme.textMuted.withValues(alpha: 0.95),
                      fontSize: 11,
                    ),
                  ),
                  value: _showScoreTarget,
                  activeTrackColor: AppTheme.accentGreen.withValues(alpha: 0.35),
                  activeThumbColor: AppTheme.accentGreen,
                  onChanged: _onScoreTargetToggled,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.onHealthWorkoutModeChanged != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.panelBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Apple Health workout',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _healthWorkoutMode.description,
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.95),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: HealthWorkoutMode.values.map((mode) {
                        final selected = mode == _healthWorkoutMode;
                        return _HealthWorkoutModeChip(
                          label: mode.label,
                          selected: selected,
                          onTap: () => _onHealthWorkoutModeSelected(mode),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Flexible(
              child: SingleChildScrollView(
                child: info == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Select a tee to view yardage and bunker details.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : _tab == _DistanceTab.yardage
                        ? DistanceCardDetailsBody(
                            distanceInfo: info,
                            teeOptions: widget.teeOptions,
                            selectedTeeFeatureId: widget.selectedTeeFeatureId,
                            onSelectTee: widget.onSelectTee,
                            onPinShot: widget.onPinShot,
                            pinnedShotCount: widget.pinnedShotCount,
                            selectedMeasurementPinIndex:
                                widget.selectedMeasurementPinIndex,
                            onSelectMeasurementPin:
                                widget.onSelectMeasurementPin,
                            onDeleteSelectedPin: widget.onDeleteSelectedPin,
                            showGreenYardages: false,
                          )
                        : DistanceCardBunkersBody(
                            distanceInfo: info,
                            teeOptions: widget.teeOptions,
                            selectedTeeFeatureId: widget.selectedTeeFeatureId,
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTabChip extends StatelessWidget {
  const _SheetTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppTheme.measureBlue.withValues(alpha: 0.2)
          : const Color(0xFF1A1A22),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.measureBlue : AppTheme.panelBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppTheme.measureBlue : AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _HealthWorkoutModeChip extends StatelessWidget {
  const _HealthWorkoutModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppTheme.accentGreen.withValues(alpha: 0.15)
          : const Color(0xFF1A1A22),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.accentGreen : AppTheme.panelBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppTheme.accentGreen : AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
