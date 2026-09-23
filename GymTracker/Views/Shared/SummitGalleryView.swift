import SwiftUI

// MARK: - Summit gallery

#if DEBUG
struct SummitGalleryView: View {
    @State private var showEmpty = false
    @State private var useLightAppearance = ProcessInfo.processInfo.arguments.contains("-SummitGalleryLight")
    @State private var unitSystem: UnitSystem = .metric

    private var snapshot: SummitSnapshot { showEmpty ? .empty : .preview }
    private var captureName: String? {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("-SummitGalleryCapture=") }
            .map { String($0.dropFirst("-SummitGalleryCapture=".count)) }
    }

    var body: some View {
        NavigationStack {
            if let captureName {
                destination(captureName)
            } else {
                galleryList
            }
        }
        .environment(\.appTheme, .black)
        .preferredColorScheme(useLightAppearance ? .light : .dark)
    }

    private var galleryList: some View {
        List {
            Section("Fixture") {
                Toggle("Empty data", isOn: $showEmpty)
                Toggle("Light appearance", isOn: $useLightAppearance)
                Picker("Units", selection: $unitSystem) {
                    Text("kg").tag(UnitSystem.metric)
                    Text("lb").tag(UnitSystem.imperial)
                }
                .pickerStyle(.segmented)
            }

            Section("History and progress") {
                NavigationLink("Summit log") { destination("log") }
                NavigationLink("Range") { destination("range") }
            }

            Section("Milestones") {
                NavigationLink("Summit reached") { destination("reached") }
                NavigationLink("Postcard") { destination("postcard") }
            }

            Section("Trail") {
                NavigationLink("Expedition") { destination("expedition") }
                NavigationLink("Cairn") { destination("cairn") }
                NavigationLink("Storm route fork") { destination("storm") }
                NavigationLink("Camp icons") { destination("icons") }
            }

            Section("App icon") {
                NavigationLink("Icon picker") { destination("picker") }
            }
        }
        .navigationTitle("Summit gallery")
    }

    @ViewBuilder
    private func destination(_ name: String) -> some View {
        switch name {
        case "log":
            ScrollView { SummitLogContent(snapshot: snapshot, unitSystem: unitSystem) }
        case "range":
            ScrollView { SummitRangeView(lifts: snapshot.lifts, unitSystem: unitSystem) }
        case "reached":
            SummitReachedGalleryScreen(unitSystem: unitSystem)
        case "postcard":
            SummitPostcardGalleryScreen()
        case "expedition":
            ScrollView { ExpeditionView(progress: snapshot.expedition, onSetOff: {}) }
        case "cairn":
            ScrollView { CairnDetailView(state: snapshot.cairn) }
        case "storm":
            ScrollView {
                SummitRouteForkView(
                    plan: .lowerRoute(
                        plannedTitle: "Legs · Heavy · Squat 5 × 5",
                        alternative: SummitLowerRoute(
                            title: "Mobility + zone 2 walk",
                            detail: "Hips and T-spine, then an easy 20 min walk",
                            minutes: 30
                        )
                    ),
                    onTakeLowerRoute: {},
                    onClimbAnyway: {}
                )
            }
        case "icons":
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 22) {
                    ForEach(0..<CampIcon.allCases.count, id: \.self) { index in
                        let icon = CampIcon.allCases[index]
                        VStack(spacing: 8) {
                            CampIconView(icon: icon, size: 44, accentActive: false)
                            Text(icon.title).font(.caption).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                    }
                }
                .padding(20)
            }
        case "picker":
            ScrollView {
                SummitAppIconPicker(totalMetres: snapshot.altitude.totalMetres)
                    .padding(20)
            }
        default:
            Text("Unknown Summit gallery capture")
        }
    }
}

private struct SummitReachedGalleryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingPostcard = false
    let unitSystem: UnitSystem

    var body: some View {
        SummitReachedView(
            moment: .preview,
            unitSystem: unitSystem,
            onShare: { showingPostcard = true },
            onDone: { dismiss() }
        )
        .sheet(isPresented: $showingPostcard) {
            SummitPostcardGalleryScreen()
        }
    }
}

private struct SummitPostcardGalleryScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SummitPostcardView(moment: .preview)
                    .frame(height: 488)
                SummitPostcardShareButton(moment: .preview)
            }
            .padding(20)
        }
    }
}
#endif
