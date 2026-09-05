import SwiftUI

/// Credits and license details for the exercise artwork bundled with Peakline.
///
/// Settings owns the route; keeping this view self-contained lets callers present it
/// from any information or about surface without coupling the legal copy to navigation.
struct ExerciseArtworkCreditsView: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        FitnessScreen(contentLayout: .eager) {
            FitnessCard(style: .hero) {
                VStack(alignment: .leading, spacing: appTheme.metrics.spacing12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(appTheme.colors.textAccent)
                        .accessibilityHidden(true)

                    Text("Exercise artwork")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("Peakline includes 302 exercises with 906 SVG animation frames from Workout Guide.")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
            }

            FitnessCard(style: .standard) {
                VStack(alignment: .leading, spacing: appTheme.metrics.spacing10) {
                    Text("Workout Guide")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("Artwork by Bryl Lim is licensed under CC BY-SA 4.0. The collection includes adaptations of original pose artwork from Everkinetic, also licensed under CC BY-SA 4.0.")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)

                    Link("View Workout Guide source", destination: URL(string: "https://github.com/bryllim/workout-guide")!)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.textAccent)

                    Link("View CC BY-SA 4.0 license", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.textAccent)
                }
            }

            FitnessCard(style: .compact) {
                VStack(alignment: .leading, spacing: appTheme.metrics.spacing8) {
                    Text("Attribution details")
                        .font(AppTypography.compactCardTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("Per-exercise and per-frame creator, source, license, and change records are retained in the bundled Workout Guide manifest. Peakline's import record and the complete license text are included in THIRD_PARTY_NOTICES.md.")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)

                    Link("View Everkinetic source", destination: URL(string: "https://github.com/everkinetic/data")!)
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textAccent)
                }
            }
        }
        .navigationTitle("Artwork Credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ExerciseArtworkCreditsView()
    }
    .environment(\.appTheme, .black)
}
