class CourseCatalogEntry {
  const CourseCatalogEntry({
    required this.name,
    required this.state,
    required this.stateCode,
    required this.city,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String state;
  final String stateCode;
  final String city;
  final double latitude;
  final double longitude;

  String get locationLabel => '$city, $state';

  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    return name.toLowerCase().contains(q) ||
        city.toLowerCase().contains(q) ||
        state.toLowerCase().contains(q) ||
        stateCode.toLowerCase().contains(q);
  }
}

typedef CourseCatalogTree = Map<String, Map<String, List<CourseCatalogEntry>>>;

CourseCatalogTree groupCourseCatalog(List<CourseCatalogEntry> entries) {
  final tree = <String, Map<String, List<CourseCatalogEntry>>>{};

  for (final entry in entries) {
    tree.putIfAbsent(entry.state, () => {});
    tree[entry.state]!.putIfAbsent(entry.city, () => []);
    tree[entry.state]![entry.city]!.add(entry);
  }

  for (final cities in tree.values) {
    for (final courses in cities.values) {
      courses.sort((a, b) => a.name.compareTo(b.name));
    }
    final sortedCities = cities.keys.toList()..sort();
    final sorted = <String, List<CourseCatalogEntry>>{};
    for (final city in sortedCities) {
      sorted[city] = cities[city]!;
    }
    cities
      ..clear()
      ..addAll(sorted);
  }

  final sortedStates = tree.keys.toList()..sort();
  final sortedTree = <String, Map<String, List<CourseCatalogEntry>>>{};
  for (final state in sortedStates) {
    sortedTree[state] = tree[state]!;
  }

  return sortedTree;
}
