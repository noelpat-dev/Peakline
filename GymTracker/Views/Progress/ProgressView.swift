import SwiftData
import SwiftUI

struct ProgressView: View {
    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    var body: some View {
        NavigationStack {
            List {
                Section("Exercises") {
                    ForEach(exercises) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.headline)
                            Text(exercise.primaryMuscleGroup.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }
}
