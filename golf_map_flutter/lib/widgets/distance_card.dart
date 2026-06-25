import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import '../utils/geo_utils.dart';

/// Yardage tab body for the distance details bottom sheet.
class DistanceCardDetailsBody extends StatelessWidget {
  const DistanceCardDetailsBody({
    super.key,
    required this.distanceInfo,
    required this.teeOptions,
    required this.selectedTeeFeatureId,
    required this.onSelectTee,
    required this.onPinShot,
    this.pinnedShotCount = 0,
    this.selectedMeasurementPinIndex,
    this.onSelectMeasurementPin,
    this.onDeleteSelectedPin,
    this.showGreenYardages = true,
  });

  final DistanceInfo distanceInfo;
  final List<TeeOption> teeOptions;
  final dynamic selectedTeeFeatureId;
  final ValueChanged<dynamic> onSelectTee;
  final VoidCallback onPinShot;
  final int pinnedShotCount;
  final int? selectedMeasurementPinIndex;
  final ValueChanged<int>? onSelectMeasurementPin;
  final VoidCallback? onDeleteSelectedPin;
  final bool showGreenYardages;

  @override
  Widget build(BuildContext context) {
    final info = distanceInfo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!info.usingGps && teeOptions.length > 1) ...[
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
            children: teeOptions.map((tee) {
              final isSelected = tee.featureId == selectedTeeFeatureId;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: tee == teeOptions.last ? 0 : 4,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onSelectTee(tee.featureId),
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
            style: TextStyle(
              color: Color(0xFF34A853),
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
        if (showGreenYardages) ...[
          const SizedBox(height: 8),
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
        ],
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
                  selectedMeasurementPinIndex == segment.shotNumber - 1,
              onTap: onSelectMeasurementPin == null
                  ? null
                  : () => onSelectMeasurementPin!(segment.shotNumber - 1),
            ),
        ],
        if (selectedMeasurementPinIndex != null &&
            onDeleteSelectedPin != null) ...[
          const SizedBox(height: 8),
          Material(
            color: const Color(0x33EF4444),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onDeleteSelectedPin,
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
                      'DELETE SHOT ${selectedMeasurementPinIndex! + 1}',
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
            onTap: onPinShot,
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
                    pinnedShotCount > 0
                        ? 'PIN (${pinnedShotCount + 1})'
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
        if (pinnedShotCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            '$pinnedShotCount pinned on hole',
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
}

/// Bunkers tab body for the distance details bottom sheet.
class DistanceCardBunkersBody extends StatelessWidget {
  const DistanceCardBunkersBody({
    super.key,
    required this.distanceInfo,
    required this.teeOptions,
    required this.selectedTeeFeatureId,
  });

  final DistanceInfo distanceInfo;
  final List<TeeOption> teeOptions;
  final dynamic selectedTeeFeatureId;

  @override
  Widget build(BuildContext context) {
    final bunkers = distanceInfo.bunkerDistances;

    if (!distanceInfo.hasBunkerReference) {
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

    final teeLabel = teeOptions
        .where((t) => t.featureId == selectedTeeFeatureId)
        .map((t) => t.label)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          distanceInfo.usingGps
              ? 'FROM GPS'
              : 'FROM TEE${teeLabel != null ? ' · $teeLabel' : ''}',
          style: const TextStyle(
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
        color: isSelected ? const Color(0x33FFD54F) : Colors.transparent,
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
