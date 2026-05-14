import SwiftUI

struct CoachView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Recommendation") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Log your first workout")
                            .font(.headline)
                        Text("Once you have workout history, the coach will explain what split to train next and whether to increase, repeat, or reduce weights.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Coach")
        }
    }
}
