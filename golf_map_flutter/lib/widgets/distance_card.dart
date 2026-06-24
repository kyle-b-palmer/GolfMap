import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import '../utils/geo_utils.dart';

enum _DistanceTab { yardage, bunkers }

class DistanceCard extends StatefulWidget {
  const DistanceCard({
    super.key,
    required this.distanceInfo,
    required this.teeOptions,
    required this.selectedTeeFeatureId,
    required this.onSelectTee,
    required this.onClear,
    required this.onPinShot,
    this.pinnedShotCount = 0,
    this.selectedMeasurementPinIndex,
    this.onSelectMeasurementPin,
    this.onDeleteSelectedPin,
  });

  final DistanceInfo distanceInfo;
  final List<TeeOption> teeOptions;
  final dynamic selectedTeeFeatureId;
  final ValueChanged<dynamic> onSelectTee;
  final VoidCallback onClear;
  final VoidCallback onPinShot;
  final int pinnedShotCount;
  final int? selectedMeasurementPinIndex;
  final ValueChanged<int>? onSelectMeasurementPin;
  final VoidCallback? onDeleteSelectedPin;

  static const _panelWidth = 168.0;

  @override
  State<DistanceCard> createState() => _DistanceCardState();
}

class _DistanceCardState extends State<DistanceCard> {
  _DistanceTab _tab = _DistanceTab.yardage;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DistanceCard._panelWidth,
      child: Material(
        color: AppTheme.panelBg,
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.measureBlue, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildTabBar()),
                    InkWell(
                      onTap: widget.onClear,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          color: Color(0xFF888888),
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_tab == _DistanceTab.yardage)
                  _buildYardageTab()
                else
                  _buildBunkersTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Row(
      children: [
        _TabChip(
          label: 'Yardage',
          selected: _tab == _DistanceTab.yardage,
          onTap: () => setState(() => _tab = _DistanceTab.yardage),
        ),
        const SizedBox(width: 4),
        _TabChip(
          label: 'Bunkers',
          selected: _tab == _DistanceTab.bunkers,
          onTap: () => setState(() => _tab = _DistanceTab.bunkers),
        ),
      ],
    );
  }

  Widget _buildYardageTab() {
    final info = widget.distanceInfo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!info.usingGps && widget.teeOptions.length > 1) ...[
          const Text(
            'TEE',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: widget.teeOptions.map((tee) {
              final isSelected = tee.featureId == widget.selectedTeeFeatureId;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: tee == widget.teeOptions.last ? 0 : 4,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onSelectTee(tee.featureId),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0x33E8D48A)
                              : const Color(0xFF1A1A22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.teeBorder
                                : AppTheme.panelBorder,
                          ),
                        ),
                        child: Text(
                          tee.label,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFFF8F6F0)
                                : AppTheme.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ] else if (info.usingGps) ...[
          const Text(
            'GPS',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF34A853),
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'TO PIN',
          style: TextStyle(
            color: Color(0xFF666666),
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        _CompactYardRow(
          label: 'F',
          fullLabel: 'Front',
          value: info.greenYardages.front,
        ),
        _CompactYardRow(
          label: 'M',
          fullLabel: 'Middle',
          value: info.greenYardages.middle,
          emphasized: true,
        ),
        _CompactYardRow(
          label: 'B',
          fullLabel: 'Back',
          value: info.greenYardages.back,
        ),
        if (info.lockedSegments.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(color: Color(0xFF2A2A2A), height: 1),
          ),
          const Text(
            'SHOTS',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          for (final segment in info.lockedSegments)
            _SelectableShotRow(
              shotNumber: segment.shotNumber,
              yards: segment.yards,
              isSelected:
                  widget.selectedMeasurementPinIndex == segment.shotNumber - 1,
              onTap: widget.onSelectMeasurementPin == null
                  ? null
                  : () => widget.onSelectMeasurementPin!(
                        segment.shotNumber - 1,
                      ),
            ),
        ],
        if (widget.selectedMeasurementPinIndex != null &&
            widget.onDeleteSelectedPin != null) ...[
          const SizedBox(height: 8),
          Material(
            color: const Color(0x33EF4444),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: widget.onDeleteSelectedPin,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF4444)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444),
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'DELETE SHOT ${widget.selectedMeasurementPinIndex! + 1}',
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Material(
          color: AppTheme.measureBlue.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: widget.onPinShot,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.measureBlue),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.place_rounded,
                    color: AppTheme.measureBlue,
                    size: 14,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.pinnedShotCount > 0
                        ? 'PIN (${widget.pinnedShotCount + 1})'
                        : 'PIN',
                    style: const TextStyle(
                      color: AppTheme.measureBlue,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          info.lockedSegments.isEmpty
              ? 'Tap map to add shot 1'
              : widget.selectedMeasurementPinIndex != null
                  ? 'Drag to move · tap again to deselect'
                  : 'Tap pin to select · outside to add shot ${info.lockedSegments.length + 1}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (widget.pinnedShotCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            '${widget.pinnedShotCount} pinned on hole',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBunkersTab() {
    final bunkers = widget.distanceInfo.bunkerDistances;

    if (!widget.distanceInfo.hasBunkerReference) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Waiting for GPS or select a tee',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (bunkers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No bunkers on this hole',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final teeLabel = widget.teeOptions
        .where((t) => t.featureId == widget.selectedTeeFeatureId)
        .map((t) => t.label)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.distanceInfo.usingGps
              ? 'FROM GPS'
              : 'FROM TEE${teeLabel != null ? ' · $teeLabel' : ''}',
          style: TextStyle(
            color: Color(0xFF666666),
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        ...bunkers.map(
          (bunker) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _BunkerRow(
              label: bunker.label,
              yards: bunker.yards,
              isNearest: bunker == bunkers.first,
            ),
          ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.measureBlue.withValues(alpha: 0.2)
                  : const Color(0xFF1A1A22),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? AppTheme.measureBlue : AppTheme.panelBorder,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppTheme.measureBlue : AppTheme.textMuted,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BunkerRow extends StatelessWidget {
  const _BunkerRow({
    required this.label,
    required this.yards,
    this.isNearest = false,
  });

  final String label;
  final int yards;
  final bool isNearest;

  static const _bunkerSand = Color(0xFFE8D48A);

  @override
  Widget build(BuildContext context) {
    final accent = isNearest ? _bunkerSand : AppTheme.textMuted;
    return Row(
      children: [
        Icon(
          Icons.terrain_rounded,
          size: 12,
          color: isNearest ? _bunkerSand : const Color(0xFF666666),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          yards < 0 ? '-${yards.abs()}' : '$yards',
          style: TextStyle(
            color: Colors.white,
            fontSize: isNearest ? 16 : 14,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        Text(
          ' y',
          style: TextStyle(
            color: accent.withValues(alpha: 0.7),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SelectableShotRow extends StatelessWidget {
  const _SelectableShotRow({
    required this.shotNumber,
    required this.yards,
    required this.isSelected,
    this.onTap,
  });

  final int shotNumber;
  final int yards;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: isSelected
            ? const Color(0x33FFD54F)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: isSelected
                  ? Border.all(color: const Color(0xFFFFD54F), width: 1)
                  : null,
            ),
            child: _CompactYardRow(
              label: '$shotNumber',
              fullLabel: 'Shot $shotNumber',
              value: yards,
              emphasized: isSelected,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactYardRow extends StatelessWidget {
  const _CompactYardRow({
    required this.label,
    required this.fullLabel,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String fullLabel;
  final int value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(
              label,
              style: TextStyle(
                color: emphasized
                    ? AppTheme.measureBlue
                    : const Color(0xFF777777),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              fullLabel,
              style: TextStyle(
                color: emphasized
                    ? AppTheme.measureBlue
                    : const Color(0xFF666666),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              color: Colors.white,
              fontSize: emphasized ? 18 : 15,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          Text(
            ' y',
            style: TextStyle(
              color: emphasized
                  ? const Color(0xAA4A9EFF)
                  : const Color(0xAA666666),
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
