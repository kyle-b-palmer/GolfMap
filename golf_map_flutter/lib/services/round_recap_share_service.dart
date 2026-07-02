import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../models/pin_type.dart';
import '../models/pinned_shot.dart';
import '../models/saved_round.dart';
import '../widgets/round_recap_share_card.dart';
import '../widgets/score_panel.dart';
import '../widgets/scorecard_share_card.dart';

class RoundRecapShareService {
  Future<void> shareRoundRecap({
    required BuildContext context,
    required SavedRound round,
    required List<HoleScoreLine> lines,
    required int totalScore,
    required int relativeToPar,
    int? longestDriveYards,
    String? bestHoleLabel,
  }) async {
    final boundaryKey = GlobalKey();
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        left: -10000,
        top: 0,
        child: RepaintBoundary(
          key: boundaryKey,
          child: RoundRecapShareCard(
            round: round,
            lines: lines,
            totalScore: totalScore,
            relativeToPar: relativeToPar,
            longestDriveYards: longestDriveYards,
            bestHoleLabel: bestHoleLabel,
          ),
        ),
      ),
    );

    overlay.insert(entry);

    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Could not render recap image');
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Could not encode recap image');
      }

      final dateLabel = ScorecardShareCard.formatDate(round.playedAt);
      final relativeLabel = ScorecardShareCard.formatRelativeToPar(relativeToPar);
      final pinCount = round.pinnedShots.values.fold<int>(
        0,
        (sum, shots) => sum + shots.length,
      );
      final shareText =
          '${round.courseName} · $dateLabel · $totalScore ($relativeLabel) · $pinCount tracked shots';

      await Share.shareXFiles(
        [
          XFile.fromData(
            byteData.buffer.asUint8List(),
            mimeType: 'image/png',
            name: 'golf-round-recap.png',
          ),
        ],
        text: shareText,
        subject: '${round.courseName} Round Recap',
      );
    } finally {
      entry.remove();
    }
  }

  static int? longestDrive(Map<String, List<PinnedShot>> pins) {
    var best = 0;
    for (final shots in pins.values) {
      for (final shot in shots) {
        if (shot.pinType == PinType.lostBall) continue;
        final yards = shot.shotYards ?? 0;
        if (yards > best) best = yards;
      }
    }
    return best > 0 ? best : null;
  }

  static String? bestHoleVsPar({
    required Map<String, int> scores,
    required Map<String, int> pars,
  }) {
    String? bestHole;
    var bestDelta = 999;
    for (final entry in scores.entries) {
      final score = entry.value;
      final par = pars[entry.key] ?? 0;
      if (score <= 0 || par <= 0) continue;
      final delta = score - par;
      if (delta < bestDelta) {
        bestDelta = delta;
        bestHole = entry.key;
      }
    }
    if (bestHole == null || bestDelta > 0) return null;
    return 'Hole $bestHole (${bestDelta == 0 ? 'par' : bestDelta})';
  }
}
