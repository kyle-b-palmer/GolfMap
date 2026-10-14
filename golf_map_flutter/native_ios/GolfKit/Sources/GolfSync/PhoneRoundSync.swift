import Foundation
import GolfCore

/// Pure translation between the phone's `RoundState` and the shared snapshot.
public enum PhoneRoundSync {
    /// Snapshot the phone publishes. Pending Watch/intent queues survive only within the same session.
    public static func snapshot(
        of round: RoundState,
        yardsToGreen: Int?,
        green: Coordinate?,
        previous: GolfRoundSharedState?
    ) -> GolfRoundSharedState {
        let sameSession = previous?.sessionId == round.sessionID
        return GolfRoundSharedState(
            holes: round.holes,
            selectedHole: round.selectedHole,
            scores: Dictionary(uniqueKeysWithValues: round.holes.map { ($0, round.score($0)) }),
            putts: Dictionary(uniqueKeysWithValues: round.holes.map { ($0, round.putts($0)) }),
            pars: Dictionary(uniqueKeysWithValues: round.holes.map { ($0, round.par($0)) }),
            handicaps: round.handicaps,
            courseName: round.courseName,
            yardsToGreen: yardsToGreen ?? -1,
            revision: max(previous?.revision ?? 0, 0) + 1,
            pendingGpsPins: sameSession ? previous?.pendingGpsPins ?? [] : [],
            pendingGpsPinUndos: sameSession ? previous?.pendingGpsPinUndos ?? [] : [],
            greenLatitude: green?.latitude ?? 0,
            greenLongitude: green?.longitude ?? 0,
            gpsRefreshRevision: sameSession ? previous?.gpsRefreshRevision ?? 0 : 0,
            sessionId: round.sessionID
        )
    }

    /// Actions for changes made by the Watch or Live Activity since the phone last looked.
    /// Order matches the Flutter app: totals, then undos, then new pins, then hole change.
    public static func actions(for changes: GolfRoundSharedState, round: RoundState) -> [RoundAction] {
        guard changes.courseName == round.courseName else { return [] }
        if !changes.sessionId.isEmpty, changes.sessionId != round.sessionID { return [] }

        var actions: [RoundAction] = [
            .applyRemoteTotals(scores: changes.scores, putts: changes.putts, selectedHole: nil)
        ]

        for undo in changes.pendingGpsPinUndos where round.holes.contains(undo.hole) {
            let superseded = changes.pendingGpsPins.contains { pin in
                if let pinId = pin.eventId, let undoId = undo.eventId { return pinId == undoId }
                return pin.isNearby(undo)
            }
            if superseded { continue }
            actions.append(.applyRemoteUndo(hole: undo.hole, point: undo.coordinate, pinEventID: undo.eventId))
        }

        for pin in changes.pendingGpsPins where round.holes.contains(pin.hole) {
            actions.append(.addPin(
                hole: pin.hole,
                point: pin.coordinate,
                source: .remote(eventID: pin.eventId, lostBall: pin.isLostBall),
                userLocation: nil,
                yardsToPin: nil,
                teeLabel: nil
            ))
        }

        if changes.selectedHole != round.selectedHole, round.holes.contains(changes.selectedHole) {
            actions.append(.selectHole(changes.selectedHole))
        }
        return actions
    }

    /// Undo entry that tells the Watch a phone-deleted pin is gone.
    public static func undoEntry(for removed: PinnedShot, hole: String) -> GolfRoundGpsPin {
        GolfRoundGpsPin(
            hole: hole,
            latitude: removed.latitude,
            longitude: removed.longitude,
            pinKind: removed.pinType == .lostBall ? "lostBall" : nil,
            eventId: removed.id
        )
    }

    /// Merges a payload received from the Watch into the phone's stored snapshot.
    /// Returns nil when the payload belongs to another session or carries no change.
    public static func mergeWatchPayload(
        _ incoming: GolfRoundSharedState,
        into current: GolfRoundSharedState?,
        activeSessionId: String
    ) -> GolfRoundSharedState? {
        guard let current else {
            guard incoming.isActiveRound else { return nil }
            if !activeSessionId.isEmpty, !incoming.sessionId.isEmpty, incoming.sessionId != activeSessionId { return nil }
            return incoming
        }
        if !incoming.sessionId.isEmpty, !current.sessionId.isEmpty, incoming.sessionId != current.sessionId {
            return nil
        }

        let hasPins = !incoming.pendingGpsPins.isEmpty
        let hasUndos = !incoming.pendingGpsPinUndos.isEmpty
        let hasScoreChanges = incoming.scores != current.scores || incoming.putts != current.putts
        let hasHoleChange = incoming.selectedHole != current.selectedHole
        let revisionAhead = incoming.revision > current.revision
        guard revisionAhead || hasPins || hasUndos || hasScoreChanges || hasHoleChange else { return nil }

        var updated = current
        updated.scores = incoming.scores
        updated.putts = incoming.putts
        updated.selectedHole = incoming.selectedHole
        updated.revision = revisionAhead ? incoming.revision : current.revision + 1

        for pin in incoming.pendingGpsPins {
            updated.pendingGpsPinUndos.removeAll { $0.isNearby(pin) && ($0.eventId == nil || pin.eventId == nil || $0.eventId == pin.eventId) }
            if !updated.pendingGpsPins.contains(where: { $0.refersToSamePin(as: pin) }) {
                updated.pendingGpsPins.append(pin)
            }
        }
        for undo in incoming.pendingGpsPinUndos {
            let superseded = incoming.pendingGpsPins.contains { added in
                if let a = added.eventId, let u = undo.eventId { return a == u }
                return added.isNearby(undo)
            }
            if superseded { continue }
            if !updated.pendingGpsPinUndos.contains(where: { $0.refersToSamePin(as: undo) }) {
                updated.pendingGpsPinUndos.append(undo)
            }
        }
        return updated
    }
}
