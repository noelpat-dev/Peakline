import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SummitSnapshotProvider {
    private(set) var snapshot: SummitSnapshot?
    private(set) var unitSystem: UnitSystem = .metric

    var totalMetres: Int? { snapshot?.altitude.totalMetres }

    func refresh(container: ModelContainer) async {}

    func metres(forCompleted session: WorkoutSession) -> Int { 0 }

    func setOff(container: ModelContainer) async {}
}
