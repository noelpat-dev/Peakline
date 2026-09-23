import SwiftUI

// MARK: - Summit gallery

#if DEBUG
struct SummitGalleryView: View {
    @State private var showEmpty = false
    @State private var useLightAppearance = false
    @State private var unitSystem: UnitSystem = .metric

    private var snapshot: SummitSnapshot { showEmpty ? .empty : .preview }

    var body: some View {
        NavigationStack {
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
                    NavigationLink("Summit log") {
                        ScrollView { SummitLogContent(snapshot: snapshot, unitSystem: unitSystem) }
                    }
                    NavigationLink("Range") {
                        ScrollView { SummitRangeView(lifts: snapshot.lifts, unitSystem: unitSystem) }
                    }
                }

                Section("Milestones") {
                    NavigationLink("Summit reached") {
                        SummitReachedGalleryScreen(unitSystem: unitSystem)
                    }
                    NavigationLink("Postcard") {
                        SummitPostcardGalleryScreen()
                    }
                }

                Section("Trail") {
                    NavigationLink("Expedition") {
                        ScrollView {
                            ExpeditionView(progress: snapshot.expedition, onSetOff: {})
                        }
                    }
                    NavigationLink("Cairn") {
                        ScrollView { CairnDetailView(state: snapshot.cairn) }
                    }
                    NavigationLink("Storm route fork") {
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
                    }
                    NavigationLink("Camp icons") {
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
                    }
                }

                Section("App icon") {
                    NavigationLink("Icon picker") {
                        ScrollView {
                            SummitAppIconPicker(totalMetres: snapshot.altitude.totalMetres)
                                .padding(20)
                        }
                    }
                }
            }
            .navigationTitle("Summit gallery")
        }
        .environment(\.appTheme, .black)
        .preferredColorScheme(useLightAppearance ? .light : .dark)
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
