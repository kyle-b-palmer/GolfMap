import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../models/club_bag.dart';
import '../services/club_bag_service.dart';

class ClubBagScreen extends StatefulWidget {
  const ClubBagScreen({super.key});

  @override
  State<ClubBagScreen> createState() => _ClubBagScreenState();
}

class _ClubBagScreenState extends State<ClubBagScreen> {
  final _clubBagService = ClubBagService();
  final _rows = <_ClubRowState>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final clubs = await _clubBagService.loadClubs();
    if (!mounted) return;
    setState(() {
      _rows
        ..clear()
        ..addAll(clubs.map(_ClubRowState.fromClub));
      _loading = false;
    });
  }

  void _addClub() {
    setState(() {
      _rows.add(_ClubRowState(name: '', yards: ''));
    });
  }

  void _removeClub(int index) {
    setState(() => _rows.removeAt(index));
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: const Text('Reset club bag?'),
        content: const Text(
          'Replace your clubs with the default carry distances.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Reset',
              style: TextStyle(color: AppTheme.accentGreen),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _clubBagService.resetToDefaults();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Club bag reset to defaults')),
    );
  }

  List<ClubDistance>? _parseClubs() {
    final clubs = <ClubDistance>[];
    for (final row in _rows) {
      final name = row.nameController.text.trim().toUpperCase();
      final yards = int.tryParse(row.yardsController.text.trim());
      if (name.isEmpty && (yards == null || yards == 0)) continue;
      if (name.isEmpty || yards == null || yards < 1 || yards > 400) {
        return null;
      }
      clubs.add(ClubDistance(name: name, carryYards: yards));
    }
    if (clubs.isEmpty) return null;
    clubs.sort((a, b) => b.carryYards.compareTo(a.carryYards));
    return clubs;
  }

  Future<void> _save() async {
    final clubs = _parseClubs();
    if (clubs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a club name and carry yards (1–400) for each row'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    await _clubBagService.saveClubs(clubs);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0E),
        foregroundColor: Colors.white,
        title: const Text('My Club Bag'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _resetDefaults,
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accentGreen,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: AppTheme.accentGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accentGreen),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const Text(
                  'Enter carry distances for each club. Suggestions use these '
                  'yards plus weather-adjusted GPS distance during a round.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'CLUB',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'CARRY (YDS)',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(width: 40),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(_rows.length, (index) {
                  final row = _rows[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: row.nameController,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(color: Colors.white),
                            decoration: _fieldDecoration(hint: '7I'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: row.yardsController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(color: Colors.white),
                            decoration: _fieldDecoration(hint: '155'),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _removeClub(index),
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _addClub,
                  icon: const Icon(Icons.add_rounded, color: AppTheme.accentGreen),
                  label: const Text(
                    'Add club',
                    style: TextStyle(color: AppTheme.accentGreen),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppTheme.accentGreen.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  InputDecoration _fieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.6)),
      filled: true,
      fillColor: AppTheme.panelBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.panelBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.panelBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.accentGreen),
      ),
    );
  }
}

class _ClubRowState {
  _ClubRowState({required String name, required String yards})
      : nameController = TextEditingController(text: name),
        yardsController = TextEditingController(text: yards);

  factory _ClubRowState.fromClub(ClubDistance club) {
    return _ClubRowState(
      name: club.name,
      yards: '${club.carryYards}',
    );
  }

  final TextEditingController nameController;
  final TextEditingController yardsController;

  void dispose() {
    nameController.dispose();
    yardsController.dispose();
  }
}
