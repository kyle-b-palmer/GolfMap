import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/golf_feature.dart';

class HoleStatsPanel extends StatelessWidget {
  const HoleStatsPanel({
    super.key,
    required this.stats,
    this.yardage,
  });

  final HoleStats stats;
  final int? yardage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatBox(label: 'PAR', value: '${stats.par}'),
        const SizedBox(height: 10),
        _StatBox(label: 'HCP', value: '${stats.handicap}'),
        if (yardage != null) ...[
          const SizedBox(height: 10),
          _StatBox(label: 'YDS', value: '$yardage'),
        ],
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
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
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
