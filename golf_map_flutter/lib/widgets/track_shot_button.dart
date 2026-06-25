import 'package:flutter/material.dart';

import '../config/app_theme.dart';

enum TrackShotAction { gps, mapPin, shotLine }

class TrackShotButton extends StatefulWidget {
  const TrackShotButton({
    super.key,
    required this.onAction,
    required this.shotLineEnabled,
    required this.mapPinEnabled,
    this.pinnedShotCount = 0,
    this.onClearPins,
  });

  final ValueChanged<TrackShotAction> onAction;
  final bool shotLineEnabled;
  final bool mapPinEnabled;
  final int pinnedShotCount;
  final VoidCallback? onClearPins;

  @override
  State<TrackShotButton> createState() => _TrackShotButtonState();
}

class _TrackShotButtonState extends State<TrackShotButton> {
  final _menuKey = GlobalKey();
  bool _menuOpen = false;

  void _toggleMenu() {
    setState(() => _menuOpen = !_menuOpen);
  }

  void _select(TrackShotAction action) {
    setState(() => _menuOpen = false);
    widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          key: _menuKey,
          color: AppTheme.panelBg,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: _toggleMenu,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.measureBlue, width: 1.5),
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
                  const Icon(
                    Icons.my_location_rounded,
                    color: AppTheme.measureBlue,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Track Shot',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _menuOpen
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_menuOpen) ...[
          const SizedBox(height: 6),
          Container(
            width: 168,
            decoration: BoxDecoration(
              color: AppTheme.panelBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.panelBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TrackShotMenuItem(
                  icon: Icons.gps_fixed_rounded,
                  label: 'GPS',
                  onTap: () => _select(TrackShotAction.gps),
                ),
                const Divider(height: 1, color: AppTheme.panelBorder),
                _TrackShotMenuItem(
                  icon: Icons.place_rounded,
                  label: 'Map Pin',
                  enabled: widget.mapPinEnabled,
                  onTap: () => _select(TrackShotAction.mapPin),
                ),
                const Divider(height: 1, color: AppTheme.panelBorder),
                _TrackShotMenuItem(
                  icon: Icons.route_rounded,
                  label: 'Shot Line',
                  active: widget.shotLineEnabled,
                  onTap: () => _select(TrackShotAction.shotLine),
                ),
                if (widget.pinnedShotCount > 0 &&
                    widget.onClearPins != null) ...[
                  const Divider(height: 1, color: AppTheme.panelBorder),
                  _TrackShotMenuItem(
                    icon: Icons.clear_rounded,
                    label: 'Clear pins (${widget.pinnedShotCount})',
                    accentColor: const Color(0xFFEF4444),
                    onTap: () {
                      setState(() => _menuOpen = false);
                      widget.onClearPins!();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TrackShotMenuItem extends StatelessWidget {
  const _TrackShotMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.active = false,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool active;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ??
        (active ? AppTheme.accentGreen : AppTheme.measureBlue);
    return Material(
      color: active ? color.withValues(alpha: 0.1) : Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: enabled ? color : AppTheme.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: enabled ? Colors.white : AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (active)
                Icon(Icons.check_rounded, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
