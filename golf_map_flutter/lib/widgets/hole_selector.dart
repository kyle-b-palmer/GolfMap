import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class HoleSelector extends StatelessWidget {
  const HoleSelector({
    super.key,
    required this.holes,
    required this.selectedHole,
    required this.onSelectHole,
  });

  final List<String> holes;
  final String selectedHole;
  final ValueChanged<String> onSelectHole;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 55,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: holes.length,
        separatorBuilder: (_, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final hole = holes[index];
          final isActive = selectedHole == hole;
          return GestureDetector(
            onTap: () => onSelectHole(hole),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isActive ? AppTheme.accentGreen : AppTheme.panelBg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive ? Colors.white : AppTheme.panelBorder,
                  width: isActive ? 2 : 1,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppTheme.accentGreen.withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  hole,
                  style: TextStyle(
                    color: isActive ? const Color(0xFF0F172A) : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
