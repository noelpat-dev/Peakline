import SwiftData
import SwiftUI

struct SplitsView: View {
    @Query(sort: \TrainingSplit.name)
    private var splits: [TrainingSplit]

    var body: some View {
        NavigationStack {
            List {
                ForEach(splits) { split in
                    NavigationLink {
                        SplitDetailView(split: split)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(split.name)
                                .font(.headline)
                            Text("\(split.exercises.count) exercises")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Splits")
            .toolbar {
                Button("Add") {}
            }
        }
    }
}

private struct SplitDetailView: View {
    let split: TrainingSplit

    var body: some View {
        List(split.exercises.sorted { $0.orderIndex < $1.orderIndex }) { exercise in
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.exerciseNameSnapshot)
                    .font(.headline)
                Text("\(exercise.targetSets) sets, \(exercise.minReps)-\(exercise.maxReps) reps")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(split.name)
    }
}
