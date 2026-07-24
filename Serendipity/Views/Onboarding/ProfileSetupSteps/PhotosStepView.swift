import SwiftUI
import PhotosUI

struct PhotosStepView: View {
    @Binding var selectedPhotos: [PhotosPickerItem]

    var body: some View {
        VStack(spacing: DQ.Spacing.xl) {
            Text("Add 2\u{2013}6 photos. The first will be your primary photo shown after proximity reveal.")
                .foregroundStyle(DQ.Colors.textSecondary)
                .multilineTextAlignment(.center)
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
                    .frame(height: DQ.Sizing.buttonHeight)
                    .background(DQ.Colors.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
                    .foregroundStyle(DQ.Colors.accent)
            }
            Text("\(selectedPhotos.count) photo(s) selected")
                .foregroundStyle(DQ.Colors.textQuaternary)
                .accessibilityLabel("\(selectedPhotos.count) photos selected")
        }
    }
}
