import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/score_panel.dart';
import '../widgets/scorecard_share_card.dart';

class ScorecardShareService {
  Future<void> shareScorecard({
    required BuildContext context,
    required String courseName,
    required DateTime playedAt,
    required List<HoleScoreLine> lines,
    required int totalScore,
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
          child: ScorecardShareCard(
            courseName: courseName,
            playedAt: playedAt,
            lines: lines,
            totalScore: totalScore,
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
        throw Exception('Could not render scorecard image');
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Could not encode scorecard image');
      }

      final dateLabel = ScorecardShareCard.formatDate(playedAt);
      final relative = lines.fold<int>(0, (sum, line) {
        if (line.score <= 0 || line.par <= 0) return sum;
        return sum + (line.score - line.par);
      });
      final relativeLabel = ScorecardShareCard.formatRelativeToPar(relative);
      final shareText =
          '$courseName · $dateLabel · $totalScore ($relativeLabel)';

      await Share.shareXFiles(
        [
          XFile.fromData(
            byteData.buffer.asUint8List(),
            mimeType: 'image/png',
            name: 'golf-scorecard.png',
          ),
        ],
        text: shareText,
        subject: '$courseName Scorecard',
      );
    } finally {
      entry.remove();
    }
  }
}
