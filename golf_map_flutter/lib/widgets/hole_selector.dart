import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';

class SidebarHolePicker extends StatefulWidget {
  const SidebarHolePicker({
    super.key,
    required this.holes,
    required this.selectedHole,
    required this.onSelectHole,
  });

  final List<String> holes;
  final String selectedHole;
  final ValueChanged<String> onSelectHole;

  @override
  State<SidebarHolePicker> createState() => _SidebarHolePickerState();
}

class _SidebarHolePickerState extends State<SidebarHolePicker> {
  late FixedExtentScrollController _controller;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final initialItem = widget.holes.isEmpty
        ? 0
        : _selectedIndex.clamp(0, widget.holes.length - 1);
    _controller = FixedExtentScrollController(initialItem: initialItem);
    _controller.addListener(_onWheelScroll);
  }

  @override
  void didUpdateWidget(SidebarHolePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedHole != widget.selectedHole ||
        oldWidget.holes != widget.holes) {
      _jumpToSelected();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onWheelScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onWheelScroll() {
    if (mounted) setState(() {});
  }

  int get _selectedIndex {
    final index = widget.holes.indexOf(widget.selectedHole);
    return index < 0 ? 0 : index;
  }

  void _jumpToSelected() {
    if (widget.holes.isEmpty) return;
    final index = _selectedIndex.clamp(0, widget.holes.length - 1);
    if (_controller.selectedItem == index) return;
    _syncing = true;
    _controller.jumpToItem(index);
    _syncing = false;
  }

  void _onWheelChanged(int index) {
    if (_syncing || widget.holes.isEmpty) return;
    final hole = widget.holes[index.clamp(0, widget.holes.length - 1)];
    if (hole == widget.selectedHole) return;
    HapticFeedback.selectionClick();
    widget.onSelectHole(hole);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.holes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 52,
      height: 72,
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
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'HOLE',
              style: TextStyle(
                color: AppTheme.accentGreen,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            child: Listener(
              onPointerDown: (_) => HapticFeedback.lightImpact(),
              child: ListWheelScrollView.useDelegate(
                controller: _controller,
                itemExtent: 22,
                diameterRatio: 1.35,
                perspective: 0.004,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: _onWheelChanged,
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: widget.holes.length,
                  builder: (context, index) {
                    final hole = widget.holes[index];
                    final isCentered = index == _controller.selectedItem;
                    return Center(
                      child: Text(
                        hole,
                        style: TextStyle(
                          color: isCentered
                              ? Colors.white
                              : AppTheme.textMuted.withValues(alpha: 0.55),
                          fontSize: isCentered ? 18 : 13,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NextHoleButton extends StatelessWidget {
  const NextHoleButton({
    super.key,
    required this.onTap,
    this.enabled = true,
  });

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Next hole',
      child: Material(
        color: AppTheme.panelBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.navigate_next_rounded,
                  size: 18,
                  color: enabled ? AppTheme.accentGreen : AppTheme.textMuted,
                ),
                const SizedBox(height: 1),
                Text(
                  'NEXT',
                  style: TextStyle(
                    color: enabled ? AppTheme.accentGreen : AppTheme.textMuted,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
