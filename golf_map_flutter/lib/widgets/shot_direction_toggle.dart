import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class ShotDirectionToggle extends StatelessWidget {
  const ShotDirectionToggle({
    super.key,
    required this.showShotDirection,
    required this.onToggle,
  });

  final bool showShotDirection;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: showShotDirection
                ? const Color(0x33EF4444)
                : AppTheme.panelBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: showShotDirection
                  ? const Color(0xFFEF4444)
                  : AppTheme.panelBorder,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                showShotDirection
                    ? Icons.route_rounded
                    : Icons.route_outlined,
                color: showShotDirection
                    ? const Color(0xFFEF4444)
                    : AppTheme.textMuted,
                size: 17,
              ),
              const SizedBox(width: 7),
              Text(
                showShotDirection ? 'Shot line on' : 'Shot line',
                style: TextStyle(
                  color: showShotDirection
                      ? const Color(0xFFFCA5A5)
                      : AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
