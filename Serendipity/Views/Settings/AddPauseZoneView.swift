import SwiftUI

// MARK: - Add Pause Zone

struct AddPauseZoneView: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (GeoFenceZone) -> Void
    @State private var label = ""
    @State private var radius = 200.0

    var body: some View {
        NavigationStack {
            VStack(spacing: DQ.Spacing.xxl) {
                DQTextField(label: "Zone name",
                            placeholder: "Zone name (e.g. Home)", text: $label,
                            isSecure: false)

                VStack(alignment: .leading, spacing: DQ.Spacing.xs) {
                    Text("Radius")
                        .font(DQ.Typography.sectionLabel())
                        .foregroundStyle(DQ.Colors.textQuaternary)
                        .tracking(0.5)
                        .textCase(.uppercase)
                    HStack(spacing: DQ.Spacing.md) {
                        Button {
                            if radius > 50 { radius -= 50 }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DQ.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(DQ.Colors.surfaceElevated)
                                .clipShape(Circle())
                        }
                        Text("\(Int(radius))m")
                            .font(DQ.Typography.bodyBold())
                            .foregroundStyle(DQ.Colors.textPrimary)
                            .frame(minWidth: 48)
                        Button {
                            if radius < 500 { radius += 50 }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DQ.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(DQ.Colors.surfaceElevated)
                                .clipShape(Circle())
                        }
                    }
                }

                Text("Your exact location is never stored — zones use anonymized geohashes.")
                    .font(DQ.Typography.caption())
                    .foregroundStyle(DQ.Colors.textQuaternary)

                Spacer()
            }
            .padding(DQ.Spacing.xl)
            .dqBackground()
            .navigationTitle("Add Pause Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DQ.Colors.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let zone = GeoFenceZone(label: label,
                                                geohash: LocationService.shared.currentGeohash ?? "",
                                                radiusMeters: radius, isActive: true)
                        onAdd(zone)
                        dismiss()
                    }
                    .disabled(label.isEmpty)
                    .foregroundStyle(label.isEmpty ? DQ.Colors.textQuaternary : DQ.Colors.accent)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
