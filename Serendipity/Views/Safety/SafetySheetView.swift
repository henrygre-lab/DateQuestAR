import SwiftUI

/// Safety sheet (docs/DESIGN_SYSTEM.md §6 row 6). Reachable from an encounter
/// via the shield icon button.
///
/// **Only the report row uses `danger`.** Ending an encounter stays neutral:
/// making every safety action look alarming is how people stop reading them,
/// and the one genuinely escalatory action loses its weight.
struct SafetySheetView: View {
    let onEndEncounter: () -> Void
    let onReport: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dq) private var p
    @State private var measuredHeight: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: DQSpace.gutter) {
            Capsule()
                .fill(p.track)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Safety options")
                    .font(DQFont.displayS)
                    .tracking(DQFont.trackDisplayS)
                    .foregroundStyle(p.text)
                Text("Nothing here notifies the other person, except ending the encounter.")
                    .font(DQFont.bodyS)
                    .foregroundStyle(p.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // §6 lists four rows. Only two ship: *Share live location* needs a
            // link service and *Check in later* needs a scheduler, and neither
            // exists. They are absent rather than greyed out — whoever opens
            // this sheet may be in a bad situation right now, so every row that
            // cannot act costs them reading time at the worst possible moment,
            // and a visible "share live location" is a false reassurance even
            // when disabled. Two rows that both work beat four where half are
            // decoration. Restore them here when the features land.
            VStack(spacing: DQSpace.tight) {
                SafetyRow(
                    symbol: "xmark",
                    title: "End encounter",
                    detail: "Re-blurs photos and closes the session"
                ) {
                    dismiss()
                    onEndEncounter()
                }
                SafetyRow(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Report this person",
                    detail: "Reviewed within 24 hours",
                    isDestructive: true
                ) {
                    dismiss()
                    onReport()
                }
            }

            Button("Cancel") { dismiss() }
                .buttonStyle(.dqGhost)
        }
        .padding(.horizontal, DQSpace.gutter)
        .padding(.top, 14)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.bg)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: SheetHeightKey.self, value: geo.size.height)
            }
        }
        .onPreferenceChange(SheetHeightKey.self) { measuredHeight = $0 }
        // Measured from the content rather than hard-coded — the previous fixed
        // height was sized against four rows and would have left dead space.
        .presentationDetents([.height(max(measuredHeight, 200))])
        .presentationCornerRadius(DQRadius.sheet)
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Row

private struct SafetyRow: View {
    let symbol: String
    let title: String
    let detail: String
    var isDestructive: Bool = false
    var action: () -> Void

    @Environment(\.dq) private var p

    private var ink: Color { isDestructive ? p.danger : p.text }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isDestructive ? p.danger : p.text2)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isDestructive ? p.danger.opacity(0.14) : p.surface2))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DQFont.uiSized(14, .bold))
                        .tracking(DQFont.track(14, em: -0.01))
                        .foregroundStyle(ink)
                    Text(detail)
                        .font(DQFont.uiSized(11.5, .medium))
                        .foregroundStyle(p.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.text3)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DQRadius.row, style: .continuous).fill(p.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DQRadius.row, style: .continuous)
                    .strokeBorder(isDestructive ? p.danger.opacity(0.34) : p.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DQRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

// MARK: - Height measurement

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
