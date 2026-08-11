import Foundation
import SwiftData
import SwiftUI

enum PeaklineSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            TrainingSplit.self,
            SplitExercise.self,
            Exercise.self,
            WorkoutSession.self,
            ExerciseLog.self,
            SetLog.self,
            Recommendation.self,
            BodyweightLog.self,
            FoodItem.self,
            FoodLogEntry.self,
            HydrationEntry.self,
            SleepSession.self,
            NapSession.self,
            DailyCoachCheckIn.self,
            CoachActionHistoryEntry.self,
            SavedCoachDeloadBlock.self,
            CoachExerciseMetadata.self,
            CoachRecommendationFeedback.self,
            CoachPreferences.self,
            CoachSplitMetadata.self
        ]
    }
}

enum PeaklineSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PeaklineSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum PeaklineModelStore {
    static var schema: Schema {
        Schema(versionedSchema: PeaklineSchemaV1.self)
    }

    static func makeContainer(
        isStoredInMemoryOnly: Bool,
        storeURL: URL? = nil
    ) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(
                "Peakline",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "Peakline",
                schema: schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitDatabase: .none
            )
        }

        return try ModelContainer(
            for: schema,
            migrationPlan: PeaklineSchemaMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

private enum PeaklineModelContainerLoadState {
    case ready(ModelContainer)
    case failed(String)
}

struct PeaklineModelContainerHost: View {
    @State private var loadState: PeaklineModelContainerLoadState

    init() {
        _loadState = State(initialValue: Self.loadContainer())
    }

    var body: some View {
        switch loadState {
        case .ready(let container):
            AppThemeProvider {
                AppStartupView()
            }
            .modelContainer(container)
        case .failed(let message):
            modelStoreRecoveryView(message: message)
        }
    }

    private func modelStoreRecoveryView(message: String) -> some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("Peakline couldn't open your data")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Your local store was left untouched. Retry after restarting the device or freeing storage; do not delete the app if you still need its local data.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)

                Button("Retry") {
                    loadState = Self.loadContainer()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("model-store-retry")
            }
            .padding(28)
            .frame(maxWidth: 520)
        }
        .accessibilityIdentifier("model-store-recovery")
    }

    private static func loadContainer() -> PeaklineModelContainerLoadState {
#if DEBUG
        let inMemory = ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore")
#else
        let inMemory = false
#endif
        do {
            return .ready(try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: inMemory))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
