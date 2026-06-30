import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/course_catalog.dart';
import '../services/course_visit_service.dart';

class CourseCatalogList extends StatefulWidget {
  const CourseCatalogList({
    super.key,
    required this.entries,
    required this.favoriteCourses,
    required this.onSelectCourse,
    required this.onToggleFavorite,
  });

  final List<CourseCatalogEntry> entries;
  final Set<String> favoriteCourses;
  final ValueChanged<String> onSelectCourse;
  final ValueChanged<String> onToggleFavorite;

  @override
  State<CourseCatalogList> createState() => _CourseCatalogListState();
}

class _CourseCatalogListState extends State<CourseCatalogList> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  List<CourseCatalogEntry> get _filteredEntries {
    if (_query.trim().isEmpty) return widget.entries;
    return widget.entries
        .where((entry) => entry.matchesQuery(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEntries;
    final isSearching = _query.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          onClear: _clearSearch,
        ),
        const SizedBox(height: 12),
        if (widget.entries.isEmpty)
          const _EmptyCatalogCard(message: 'No courses available.')
        else if (filtered.isEmpty)
          const _EmptyCatalogCard(
            message: 'No courses match your search.',
          )
        else if (isSearching)
          ...filtered.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CourseResultCard.fromCatalog(
                entry: entry,
                isFavorite: widget.favoriteCourses.contains(entry.name),
                onToggleFavorite: () => widget.onToggleFavorite(entry.name),
                onTap: () => widget.onSelectCourse(entry.name),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppTheme.panelBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.panelBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: groupCourseCatalog(filtered).entries.map((stateEntry) {
                final state = stateEntry.key;
                final cities = stateEntry.value;
                final courseCount = cities.values
                    .fold<int>(0, (sum, courses) => sum + courses.length);

                return _CatalogExpansionTile(
                  tier: _CatalogTier.state,
                  title: state,
                  subtitle:
                      '$courseCount course${courseCount == 1 ? '' : 's'}',
                  children: cities.entries.expand((cityEntry) {
                    final city = cityEntry.key;
                    final courses = cityEntry.value;

                    return [
                      _CatalogExpansionTile(
                        tier: _CatalogTier.city,
                        title: city,
                        subtitle:
                            '${courses.length} course${courses.length == 1 ? '' : 's'}',
                        children: courses
                            .map(
                              (course) => _CourseListTile(
                                course: course.name,
                                isFavorite: widget.favoriteCourses
                                    .contains(course.name),
                                onToggleFavorite: () =>
                                    widget.onToggleFavorite(course.name),
                                onTap: () =>
                                    widget.onSelectCourse(course.name),
                              ),
                            )
                            .toList(),
                      ),
                    ];
                  }).toList(),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Search state, city, or course',
        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
        prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
              ),
        filled: true,
        fillColor: AppTheme.panelBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.panelBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.accentGreen),
        ),
      ),
    );
  }
}

enum _CatalogTier { state, city }

class _CatalogExpansionTile extends StatelessWidget {
  const _CatalogExpansionTile({
    required this.tier,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final _CatalogTier tier;
  final String title;
  final String subtitle;
  final List<Widget> children;

  static const _baseIndent = 16.0;
  static const _indentStep = 18.0;

  double get _leftIndent => _baseIndent + tier.index * _indentStep;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.fromLTRB(_leftIndent, 4, 16, 4),
        childrenPadding: EdgeInsets.only(left: _leftIndent, right: 8, bottom: 4),
        iconColor: AppTheme.accentGreen,
        collapsedIconColor: AppTheme.textMuted,
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: tier == _CatalogTier.state ? 16 : 15,
            fontWeight:
                tier == _CatalogTier.state ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: tier == _CatalogTier.state ? 12 : 11,
          ),
        ),
        children: children,
      ),
    );
  }
}

class _CourseListTile extends StatelessWidget {
  const _CourseListTile({
    required this.course,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  final String course;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  static const _leftIndent =
      _CatalogExpansionTile._baseIndent + _CatalogExpansionTile._indentStep * 2;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.fromLTRB(_leftIndent, 6, 12, 6),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.golf_course_rounded,
                  color: AppTheme.accentGreen,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  course,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _FavoriteStarButton(
                isFavorite: isFavorite,
                onPressed: onToggleFavorite,
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppTheme.textMuted,
                size: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FavoritesSection extends StatelessWidget {
  const FavoritesSection({
    super.key,
    required this.favoriteCourses,
    required this.catalog,
    required this.onSelectCourse,
    required this.onToggleFavorite,
  });

  final List<String> favoriteCourses;
  final List<CourseCatalogEntry> catalog;
  final ValueChanged<String> onSelectCourse;
  final ValueChanged<String> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (favoriteCourses.isEmpty) return const SizedBox.shrink();

    final catalogByName = {
      for (final entry in catalog) entry.name: entry,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...favoriteCourses.map((courseName) {
          final catalogEntry = catalogByName[courseName];
          final subtitle = catalogEntry?.locationLabel ?? 'Pinned course';

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CourseResultCard(
              title: courseName,
              subtitle: subtitle,
              isFavorite: true,
              onToggleFavorite: () => onToggleFavorite(courseName),
              onTap: () => onSelectCourse(courseName),
            ),
          );
        }),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _FavoriteStarButton extends StatelessWidget {
  const _FavoriteStarButton({
    required this.isFavorite,
    required this.onPressed,
  });

  final bool isFavorite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(
        isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
        color: isFavorite ? const Color(0xFFFFC107) : AppTheme.textMuted,
        size: 22,
      ),
    );
  }
}

class CommonlyVisitedSection extends StatelessWidget {
  const CommonlyVisitedSection({
    super.key,
    required this.entries,
    required this.catalog,
    required this.favoriteCourses,
    required this.onSelectCourse,
    required this.onToggleFavorite,
  });

  final List<CommonlyVisitedEntry> entries;
  final List<CourseCatalogEntry> catalog;
  final Set<String> favoriteCourses;
  final ValueChanged<String> onSelectCourse;
  final ValueChanged<String> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final catalogByName = {
      for (final entry in catalog) entry.name: entry,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...entries.map((entry) {
          final catalogEntry = catalogByName[entry.courseName];
          final location = catalogEntry?.locationLabel;
          final subtitle = entry.countLabel;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CourseResultCard(
              title: entry.courseName,
              subtitle: location == null ? subtitle : '$location · $subtitle',
              isFavorite: favoriteCourses.contains(entry.courseName),
              onToggleFavorite: () => onToggleFavorite(entry.courseName),
              onTap: () => onSelectCourse(entry.courseName),
            ),
          );
        }),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _CourseResultCard extends StatelessWidget {
  const _CourseResultCard({
    required this.title,
    required this.subtitle,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  factory _CourseResultCard.fromCatalog({
    required CourseCatalogEntry entry,
    required bool isFavorite,
    required VoidCallback onToggleFavorite,
    required VoidCallback onTap,
  }) {
    return _CourseResultCard(
      title: entry.name,
      subtitle: entry.locationLabel,
      isFavorite: isFavorite,
      onToggleFavorite: onToggleFavorite,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.panelBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.panelBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.golf_course_rounded,
                  color: AppTheme.accentGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _FavoriteStarButton(
                isFavorite: isFavorite,
                onPressed: onToggleFavorite,
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppTheme.textMuted,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCatalogCard extends StatelessWidget {
  const _EmptyCatalogCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.panelBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
      ),
    );
  }
}
