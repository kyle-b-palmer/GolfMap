import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class CourseSelector extends StatelessWidget {
  const CourseSelector({
    super.key,
    required this.courses,
    required this.selectedCourse,
    required this.showDropdown,
    required this.onToggleDropdown,
    required this.onSelectCourse,
  });

  final List<String> courses;
  final String? selectedCourse;
  final bool showDropdown;
  final VoidCallback onToggleDropdown;
  final ValueChanged<String> onSelectCourse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggleDropdown,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.panelBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.panelBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'COURSE',
                        style: TextStyle(
                          color: AppTheme.accentGreen,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedCourse ?? 'Select Course',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    showDropdown
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.accentGreen,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDropdown) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.panelBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.panelBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: courses.map((course) {
                final isActive = selectedCourse == course;
                return Material(
                  color: isActive
                      ? AppTheme.accentGreen.withValues(alpha: 0.08)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelectCourse(course),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 15,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF222222)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            course,
                            style: TextStyle(
                              color: isActive
                                  ? AppTheme.accentGreen
                                  : AppTheme.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isActive)
                            const Icon(
                              Icons.check_rounded,
                              color: AppTheme.accentGreen,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
