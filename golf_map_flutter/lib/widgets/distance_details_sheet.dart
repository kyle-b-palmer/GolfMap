import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import '../utils/geo_utils.dart';
import 'distance_card.dart';

enum _DistanceTab { yardage, bunkers }

class DistanceDetailsSheet extends StatefulWidget {
  const DistanceDetailsSheet({
    super.key,
    required this.courseName,
    required this.selectedHole,
    required this.par,
    required this.distanceInfo,
    required this.teeOptions,
    required this.selectedTeeFeatureId,
    required this.onSelectTee,
    required this.onPinShot,
    this.pinnedShotCount = 0,
    this.selectedMeasurementPinIndex,
    this.onSelectMeasurementPin,
    this.onDeleteSelectedPin,
  });

  final String courseName;
  final String selectedHole;
  final int par;
  final DistanceInfo distanceInfo;
  final List<TeeOption> teeOptions;
  final dynamic selectedTeeFeatureId;
  final ValueChanged<dynamic> onSelectTee;
  final VoidCallback onPinShot;
  final int pinnedShotCount;
  final int? selectedMeasurementPinIndex;
  final ValueChanged<int>? onSelectMeasurementPin;
  final VoidCallback? onDeleteSelectedPin;

  static Future<void> show(
    BuildContext context, {
    required String courseName,
    required String selectedHole,
    required int par,
    required DistanceInfo distanceInfo,
    required List<TeeOption> teeOptions,
    required dynamic selectedTeeFeatureId,
    required ValueChanged<dynamic> onSelectTee,
    required VoidCallback onPinShot,
    int pinnedShotCount = 0,
    int? selectedMeasurementPinIndex,
    ValueChanged<int>? onSelectMeasurementPin,
    VoidCallback? onDeleteSelectedPin,
  }) {
    return showModalBottomSheet<void>(
      context: context,
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
        ),
      ),
    );
  }

  @override
  State<DistanceDetailsSheet> createState() => _DistanceDetailsSheetState();
}

class _DistanceDetailsSheetState extends State<DistanceDetailsSheet> {
  _DistanceTab _tab = _DistanceTab.yardage;

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
            Flexible(
              child: SingleChildScrollView(
                child: _tab == _DistanceTab.yardage
                    ? DistanceCardDetailsBody(
                        distanceInfo: info,
                        teeOptions: widget.teeOptions,
                        selectedTeeFeatureId: widget.selectedTeeFeatureId,
                        onSelectTee: widget.onSelectTee,
                        onPinShot: widget.onPinShot,
                        pinnedShotCount: widget.pinnedShotCount,
                        selectedMeasurementPinIndex:
                            widget.selectedMeasurementPinIndex,
                        onSelectMeasurementPin: widget.onSelectMeasurementPin,
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
