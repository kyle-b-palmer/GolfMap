import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import '../services/club_suggestion_service.dart';

class HoleStatsPanel extends StatelessWidget {
  const HoleStatsPanel({
    super.key,
    required this.stats,
    this.yardage,
    this.gpsGreenYardages,
    this.clubSuggestion,
    this.playsLikeYards,
    this.yardsFromLastPin,
    this.clubUsesAimTarget = false,
    this.onEditClubBag,
  });

  final HoleStats stats;
  final int? yardage;
  final GreenYardages? gpsGreenYardages;
  final ClubSuggestion? clubSuggestion;
  final int? playsLikeYards;
  final int? yardsFromLastPin;
  final bool clubUsesAimTarget;
  final VoidCallback? onEditClubBag;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatBox(label: 'PAR', value: '${stats.par}'),
        const SizedBox(height: 8),
        _StatBox(label: 'HCP', value: '${stats.handicap}'),
        if (yardage != null) ...[
          const SizedBox(height: 8),
          _StatBox(label: 'YDS', value: '$yardage', compactValue: true),
        ],
        if (gpsGreenYardages != null) ...[
          const SizedBox(height: 8),
          _GpsGreenYardageBox(
            yardages: gpsGreenYardages!,
            playsLikeYards: playsLikeYards,
          ),
        ],
        if (yardsFromLastPin != null) ...[
          const SizedBox(height: 8),
          _StatBox(
            label: 'DIST',
            value: '$yardsFromLastPin',
            compactValue: true,
          ),
        ],
        if (clubSuggestion != null) ...[
          const SizedBox(height: 8),
          _ClubSuggestionBox(
            suggestion: clubSuggestion!,
            usesAimTarget: clubUsesAimTarget,
            onEdit: onEditClubBag,
          ),
        ],
      ],
    );
  }
}

/// Interactive map controls — lives on the left below the hole picker.
class MapActionPanel extends StatelessWidget {
  static const _actionGap = 6.0;

  const MapActionPanel({
    super.key,
    this.showMapOverlay = true,
    this.onToggleMapOverlay,
    this.showBunkerDistancesOnMap = false,
    this.onToggleBunkerDistancesOnMap,
    this.onOpenDetails,
    this.onOpenGpsToGreen,
    this.onToggleDispersion,
    this.showDispersion = false,
    this.onToggleAutoAdvance,
    this.autoAdvanceHole = true,
    this.onEditClubBag,
    this.showClubBagButton = false,
    this.holeLocked = false,
    this.onToggleHoleLock,
    this.clubAimPlacementMode = false,
    this.hasClubAimPoint = false,
    this.onToggleClubAimPlacement,
    this.onClearClubAimPoint,
    this.gpsSimMode = false,
    this.gpsSimPlacementMode = false,
    this.onToggleGpsSimMode,
    this.onToggleGpsSimPlacement,
  });

  final bool showMapOverlay;
  final ValueChanged<bool>? onToggleMapOverlay;
  final bool showBunkerDistancesOnMap;
  final ValueChanged<bool>? onToggleBunkerDistancesOnMap;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onOpenGpsToGreen;
  final ValueChanged<bool>? onToggleDispersion;
  final bool showDispersion;
  final ValueChanged<bool>? onToggleAutoAdvance;
  final bool autoAdvanceHole;
  final VoidCallback? onEditClubBag;
  final bool showClubBagButton;
  final bool holeLocked;
  final VoidCallback? onToggleHoleLock;
  final bool clubAimPlacementMode;
  final bool hasClubAimPoint;
  final VoidCallback? onToggleClubAimPlacement;
  final VoidCallback? onClearClubAimPoint;
  final bool gpsSimMode;
  final bool gpsSimPlacementMode;
  final VoidCallback? onToggleGpsSimMode;
  final VoidCallback? onToggleGpsSimPlacement;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onToggleHoleLock != null) ...[
          MapSidebarIconButton(
            icon: holeLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            tooltip: holeLocked
                ? 'Unlock hole to add shots'
                : 'Lock hole as complete',
            active: holeLocked,
            activeColor: const Color(0xFFE8D48A),
            onTap: onToggleHoleLock!,
          ),
          const SizedBox(height: _actionGap),
        ],
        if (showClubBagButton && onEditClubBag != null) ...[
          MapSidebarIconButton(
            icon: Icons.golf_course_rounded,
            tooltip: 'Edit club bag',
            active: false,
            onTap: onEditClubBag!,
          ),
          const SizedBox(height: _actionGap),
        ],
        if (onToggleClubAimPlacement != null) ...[
          MapSidebarIconButton(
            icon: Icons.adjust_rounded,
            tooltip: clubAimPlacementMode
                ? 'Tap map to set club target'
                : 'Set club target on map',
            active: clubAimPlacementMode || hasClubAimPoint,
            activeColor: const Color(0xFF7DD3FC),
            onTap: onToggleClubAimPlacement!,
          ),
          const SizedBox(height: _actionGap),
        ],
        if (hasClubAimPoint && onClearClubAimPoint != null) ...[
          MapSidebarIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Clear club target',
            active: true,
            activeColor: const Color(0xFF7DD3FC),
            onTap: onClearClubAimPoint!,
          ),
          const SizedBox(height: _actionGap),
        ],
        if (onToggleGpsSimMode != null) ...[
          MapSidebarIconButton(
            icon: gpsSimMode ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
            tooltip: gpsSimMode
                ? 'GPS test mode on — using simulated position'
                : 'GPS test mode — simulate position on map',
            active: gpsSimMode,
            activeColor: const Color(0xFFCE93D8),
            onTap: onToggleGpsSimMode!,
          ),
          const SizedBox(height: _actionGap),
        ],
        if (gpsSimMode && onToggleGpsSimPlacement != null) ...[
          MapSidebarIconButton(
            icon: Icons.add_location_alt_rounded,
            tooltip: gpsSimPlacementMode
                ? 'Tap map to place test GPS'
                : 'Place test GPS on map',
            active: gpsSimPlacementMode,
            activeColor: const Color(0xFFCE93D8),
            onTap: onToggleGpsSimPlacement!,
          ),
          const SizedBox(height: _actionGap),
        ],
        if (onToggleMapOverlay != null && !kIsWeb) ...[
          MapSidebarIconButton(
            icon: Icons.layers_rounded,
            tooltip: showMapOverlay
                ? (Platform.isIOS ? 'Hide Apple Maps' : 'Hide map overlay')
                : (Platform.isIOS ? 'Show Apple Maps' : 'Show map overlay'),
            active: showMapOverlay,
            activeColor: AppTheme.accentGreen,
            onTap: () => onToggleMapOverlay!(!showMapOverlay),
          ),
          const SizedBox(height: _actionGap),
        ],
        if (onToggleBunkerDistancesOnMap != null) ...[
          MapSidebarIconButton(
            icon: Icons.terrain_rounded,
            tooltip: showBunkerDistancesOnMap
                ? 'Hide bunker distances'
                : 'Show bunker distances',
            active: showBunkerDistancesOnMap,
            activeColor: const Color(0xFFE8D48A),
            onTap: () => onToggleBunkerDistancesOnMap!(
              !showBunkerDistancesOnMap,
            ),
          ),
          const SizedBox(height: _actionGap),
        ],
        if (onToggleDispersion != null) ...[
          MapSidebarIconButton(
            icon: Icons.blur_on_rounded,
            tooltip: showDispersion
                ? 'Hide shot dispersion'
                : 'Show shot dispersion',
            active: showDispersion,
            activeColor: AppTheme.accentGreen,
            onTap: () => onToggleDispersion!(!showDispersion),
          ),
          const SizedBox(height: _actionGap),
        ],
        if (onToggleAutoAdvance != null) ...[
          MapSidebarIconButton(
            icon: Icons.skip_next_rounded,
            tooltip: autoAdvanceHole
                ? 'Auto-advance hole on'
                : 'Auto-advance hole off',
            active: autoAdvanceHole,
            activeColor: AppTheme.accentGreen,
            onTap: () => onToggleAutoAdvance!(!autoAdvanceHole),
          ),
          const SizedBox(height: _actionGap),
        ],
        if (onOpenDetails != null) ...[
          MapSidebarIconButton(
            icon: Icons.info_outline_rounded,
            tooltip: 'Hole details',
            onTap: onOpenDetails!,
          ),
          const SizedBox(height: _actionGap),
        ],
        if (onOpenGpsToGreen != null) ...[
          MapSidebarIconButton(
            icon: Icons.flag_rounded,
            tooltip: 'GPS to Green',
            onTap: onOpenGpsToGreen!,
          ),
        ],
      ],
    );
  }
}

/// Shown above bottom-left controls when a map pin or shot node is selected.
class DeleteSelectedPinButton extends StatelessWidget {
  const DeleteSelectedPinButton({
    super.key,
    required this.onTap,
    this.label = 'Delete pin',
  });

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: const Color(0xE61A1A22),
        elevation: 6,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFEF4444),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _GpsGreenYardageBox extends StatelessWidget {
  const _GpsGreenYardageBox({
    required this.yardages,
    this.playsLikeYards,
  });

  final GreenYardages yardages;
  final int? playsLikeYards;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: AppTheme.panelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.measureBlue.withValues(alpha: 0.7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.gps_fixed_rounded,
            size: 14,
            color: AppTheme.measureBlue.withValues(alpha: 0.95),
          ),
          const SizedBox(height: 4),
          _GreenYardRow(label: 'F', yards: yardages.front),
          const SizedBox(height: 2),
          _GreenYardRow(
            label: 'P',
            yards: yardages.middle,
            emphasized: true,
          ),
          const SizedBox(height: 2),
          _GreenYardRow(label: 'B', yards: yardages.back),
          if (playsLikeYards != null &&
              (playsLikeYards! - yardages.middle).abs() >= 2) ...[
            const SizedBox(height: 4),
            Text(
              'PLAY $playsLikeYards',
              style: TextStyle(
                color: AppTheme.measureBlue.withValues(alpha: 0.95),
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClubSuggestionBox extends StatelessWidget {
  const _ClubSuggestionBox({
    required this.suggestion,
    this.usesAimTarget = false,
    this.onEdit,
  });

  final ClubSuggestion suggestion;
  final bool usesAimTarget;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onEdit,
      child: Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: AppTheme.panelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.55)),
      ),
      child: Column(
        children: [
          Text(
            usesAimTarget ? 'CLUB·TGT' : 'CLUB',
            style: TextStyle(
              color: AppTheme.textMuted.withValues(alpha: 0.9),
              fontSize: 7,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            suggestion.club,
            style: const TextStyle(
              color: AppTheme.accentGreen,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '${suggestion.targetYards}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (suggestion.alternateClub != null)
            Text(
              'or ${suggestion.alternateClub}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 8),
            ),
        ],
      ),
    ),
    );
  }
}

class _GreenYardRow extends StatelessWidget {
  const _GreenYardRow({
    required this.label,
    required this.yards,
    this.emphasized = false,
  });

  final String label;
  final int yards;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            color: emphasized ? AppTheme.measureBlue : AppTheme.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '$yards',
          style: TextStyle(
            color: emphasized ? Colors.white : const Color(0xFFCCCCCC),
            fontSize: emphasized ? 13 : 11,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class MapSidebarIconButton extends StatelessWidget {
  const MapSidebarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final accent = activeColor ?? AppTheme.measureBlue;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? accent.withValues(alpha: 0.2) : AppTheme.panelBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? accent : AppTheme.panelBorder,
                width: active ? 1.5 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                icon,
                size: 20,
                color: active ? accent : AppTheme.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    this.compactValue = false,
  });

  final String label;
  final String value;
  final bool compactValue;

  @override
  Widget build(BuildContext context) {
    final valueFontSize = compactValue ? 17.0 : 22.0;

    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: AppTheme.panelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.panelBorder),
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
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.accentGreen,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
