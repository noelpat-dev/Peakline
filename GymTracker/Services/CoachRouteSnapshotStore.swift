import Foundation

/// Shared Coach route publication boundary for startup, Today, and Coach.
/// Callers prepare values; this store owns generation ordering and publication.
@MainActor
final class CoachRouteSnapshotStore {
    static let shared = CoachRouteSnapshotStore()

    private(set) var snapshot: CoachRouteRenderSnapshot?
    private(set) var signature: String?
    private(set) var sourceGeneration = 0

    private init() {}

    func update(
        snapshot: CoachRouteRenderSnapshot,
        signature: String,
        source: String,
        sourceGeneration: Int? = nil
    ) {
        let generation = sourceGeneration ?? snapshot.sourceGeneration
        guard generation >= self.sourceGeneration else {
            PerformanceTracer.mark(
                .coachSnapshot,
                "route_snapshot_store reject_older source=\(source) generation=\(generation) current=\(self.sourceGeneration)"
            )
            return
        }
        let normalizedSnapshot = snapshot.sourceGeneration == generation
            ? snapshot
            : snapshot.withSourceGeneration(generation)
        PerformanceTracer.mark(
            .coachSnapshot,
            "route_snapshot_store update_begin source=\(source) generation=\(generation) main=\(Thread.isMainThread) contains_model_checkIn=\(normalizedSnapshot.intelligence.readiness.checkIn != nil)"
        )
        self.snapshot = normalizedSnapshot
        self.signature = signature
        self.sourceGeneration = generation
        PerformanceTracer.mark(.coachSnapshot, "route_snapshot_store update source=\(source)")
        PerformanceTracer.mark(
            .coachSnapshot,
            "route_snapshot_store update_end source=\(source) generation=\(generation) stored_model_checkIn=\(self.snapshot?.intelligence.readiness.checkIn != nil)"
        )
    }

    func update(
        intelligence: CoachIntelligenceSnapshot,
        trainingCall: TrainingCallSnapshot,
        recommendedSplit: WorkoutPreviewSplit?,
        fallback: CoachRouteRenderSnapshot? = nil,
        signature: String,
        sourceGeneration: Int,
        source: String
    ) {
        guard let base = snapshot ?? fallback else {
            PerformanceTracer.mark(
                .coachSnapshot,
                "route_snapshot_store skip incomplete_update source=\(source) generation=\(sourceGeneration)"
            )
            return
        }
        update(
            snapshot: base.replacing(
                intelligence: intelligence,
                trainingCall: trainingCall,
                recommendedSplit: recommendedSplit,
                sourceGeneration: sourceGeneration
            ),
            signature: signature,
            source: source,
            sourceGeneration: sourceGeneration
        )
    }

    func invalidate(source: String) {
        snapshot = nil
        signature = nil
        PerformanceTracer.mark(.coachSnapshot, "route_snapshot_store invalidate source=\(source)")
    }

    /// Reserves a monotonic publication generation before any asynchronous
    /// preparation starts. A late completion carrying an older reservation is
    /// rejected by `update`, regardless of which input family changed.
    func nextSourceGeneration() -> Int {
        sourceGeneration &+= 1
        return sourceGeneration
    }

    func resetForTesting() {
        snapshot = nil
        signature = nil
        sourceGeneration = 0
    }
}
