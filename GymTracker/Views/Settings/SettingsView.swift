import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    if let profile = profiles.first {
                        LabeledContent("Goal", value: profile.goal.displayName)
                        LabeledContent("Experience", value: profile.experienceLevel.displayName)
                        LabeledContent("Training days", value: "\(profile.trainingDaysPerWeek)")
                        LabeledContent("Units", value: profile.unitSystem == .metric ? "kg" : "lb")
                    } else {
                        Text("Profile will be created on first launch.")
                    }
                }

                Section("Safety") {
                    Text("This app provides general fitness tracking and training suggestions based on your logged workouts. It is not medical advice. Stop exercising and seek professional advice if you experience pain, dizziness, or symptoms that concern you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
