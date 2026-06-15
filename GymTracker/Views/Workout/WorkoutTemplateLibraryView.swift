import SwiftUI

struct WorkoutTemplateLibraryView: View {
    @Environment(\.appTheme) private var appTheme

    @State private var templates: [CustomWorkoutTemplate] = []
    @State private var previewSplit: WorkoutPreviewSplit?
    @State private var pendingDelete: CustomWorkoutTemplate?
    @State private var errorText: String?

    private let store = WorkoutTemplateStore()
    private let reuseBuilder = WorkoutReuseBuilder()

    var body: some View {
        FitnessScreen(
            title: "Templates",
            subtitle: "Start from saved local workout plans.",
            systemImage: "rectangle.stack"
        ) {
            if templates.isEmpty {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No templates yet")
                            .font(.headline)
                        Text("Save a good completed workout as a template from Session Summary or History.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }
            } else {
                ForEach(templates) { template in
                    WorkoutTemplateRow(
                        template: template,
                        start: {
                            let split = reuseBuilder.previewSplit(from: template)
                            PerformanceTracer.mark(.previewRouteTap, "source=template split=\(split.name) mode=\(WorkoutMode.full.rawValue)")
                            previewSplit = split
                        },
                        delete: {
                            pendingDelete = template
                        }
                    )
                }
            }

            if let errorText {
                FitnessCard {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.dangerColor)
                }
            }
        }
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $previewSplit) { split in
            WorkoutPreviewRouteView(split: split, initialMode: .full)
        }
        .alert("Delete template?", isPresented: deleteAlertBinding) {
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
            Button("Delete", role: .destructive) {
                deletePendingTemplate()
            }
        } message: {
            Text("This only removes the saved template. Workout history stays unchanged.")
        }
        .onAppear(perform: reload)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding {
            pendingDelete != nil
        } set: { isShowing in
            if !isShowing {
                pendingDelete = nil
            }
        }
    }

    private func reload() {
        templates = store.loadTemplates()
    }

    private func deletePendingTemplate() {
        guard let pendingDelete else { return }
        do {
            try store.delete(pendingDelete)
            self.pendingDelete = nil
            reload()
        } catch {
            errorText = "Could not delete template: \(error.localizedDescription)"
        }
    }
}
