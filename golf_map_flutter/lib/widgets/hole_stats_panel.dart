import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import 'hole_selector.dart';

class HoleStatsPanel extends StatelessWidget {
  const HoleStatsPanel({
    super.key,
    required this.stats,
    required this.holes,
    required this.selectedHole,
    required this.onSelectHole,
    this.onNextHole,
    this.yardage,
    this.greenYardages,
    this.showBunkerDistancesOnMap = true,
    this.onToggleBunkerDistancesOnMap,
    this.onOpenDetails,
    this.onOpenGpsToGreen,
  });

  final HoleStats stats;
  final List<String> holes;
  final String selectedHole;
  final ValueChanged<String> onSelectHole;
  final VoidCallback? onNextHole;
  final int? yardage;
  final GreenYardages? greenYardages;
  final bool showBunkerDistancesOnMap;
  final ValueChanged<bool>? onToggleBunkerDistancesOnMap;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onOpenGpsToGreen;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SidebarHolePicker(
          holes: holes,
          selectedHole: selectedHole,
          onSelectHole: onSelectHole,
        ),
        if (onNextHole != null) ...[
          const SizedBox(height: 8),
          NextHoleButton(
            onTap: onNextHole!,
            enabled: holes.length > 1,
          ),
        ],
        const SizedBox(height: 8),
        _StatBox(label: 'PAR', value: '${stats.par}'),
        const SizedBox(height: 8),
        _StatBox(label: 'HCP', value: '${stats.handicap}'),
        if (yardage != null) ...[
          const SizedBox(height: 8),
          _StatBox(label: 'YDS', value: '$yardage', compactValue: true),
        ],
        if (greenYardages != null) ...[
          const SizedBox(height: 8),
          _GreenYardageBox(yardages: greenYardages!),
        ],
        if (onToggleBunkerDistancesOnMap != null) ...[
          const SizedBox(height: 8),
          _SidebarIconButton(
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
        ],
        if (onOpenDetails != null) ...[
          const SizedBox(height: 8),
          _SidebarIconButton(
            icon: Icons.info_outline_rounded,
            tooltip: 'Hole details',
            onTap: onOpenDetails!,
          ),
        ],
        if (onOpenGpsToGreen != null) ...[
          const SizedBox(height: 8),
          _SidebarIconButton(
            icon: Icons.flag_rounded,
            tooltip: 'GPS to Green',
            onTap: onOpenGpsToGreen!,
          ),
        ],
      ],
    );
  }
}

class _GreenYardageBox extends StatelessWidget {
  const _GreenYardageBox({required this.yardages});

  final GreenYardages yardages;

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
        children: [
          const Text(
            'GRN',
            style: TextStyle(
              color: AppTheme.measureBlue,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
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
        ],
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

class _SidebarIconButton extends StatelessWidget {
  const _SidebarIconButton({
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
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
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
