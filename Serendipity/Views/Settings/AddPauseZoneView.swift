import SwiftUI

// MARK: - Add Pause Zone
//
// DesignSystem v2 skin. The zone written on "Add" is unchanged: same label,
// same geohash source, same radius bounds (50–500 m in 50 m steps).

struct AddPauseZoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dq) private var p
    var onAdd: (GeoFenceZone) -> Void

    @State private var label = ""
    @State private var radius = 200.0

    private var radiusSteps: Binding<Int> {
        Binding(get: { Int(radius) }, set: { radius = Double($0) })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                p.bg.ignoresSafeArea()

                VStack(spacing: DQSpace.gutter) {
                    DQTopBar(title: "Add pause zone", style: .pushed, onBack: { dismiss() }) {
                        DQTopBarAction(title: "Add") {
                            let zone = GeoFenceZone(
                                label: label,
                                geohash: LocationService.shared.currentGeohash ?? "",
                                radiusMeters: radius,
                                isActive: true
                            )
                            onAdd(zone)
                            dismiss()
                        }
                        .disabled(label.isEmpty)
                        .opacity(label.isEmpty ? 0.45 : 1)
                    }

                    DQTextField(
                        label: "Zone name",
                        placeholder: "Zone name (e.g. Home)",
                        text: $label
                    )

                    DQGroup {
                        DQStepperRow(
                            label: "Radius",
                            value: radiusSteps,
                            range: 50...500,
                            step: 50,
                            format: { "\($0) m" }
                        )
                    }

                    DQFootnote(
                        text: "Your exact location is never stored — zones use anonymized geohashes."
                    )

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DQSpace.gutter)
                .padding(.top, DQSpace.safeTop)
                .padding(.bottom, DQSpace.safeBottom)
            }
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
