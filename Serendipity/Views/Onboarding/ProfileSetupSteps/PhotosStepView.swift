import SwiftUI
import PhotosUI

struct PhotosStepView: View {
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Environment(\.dq) private var p

    var body: some View {
        VStack(spacing: DQSpace.gutter) {
            Text("Add 2–6 photos. The first will be your primary photo shown after proximity reveal.")
                .font(DQFont.body)
                .foregroundStyle(p.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                Text("Choose photos")
                    .font(DQFont.uiSized(14, .semibold))
                    .foregroundStyle(p.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: DQSize.ghostHeight)
                    .overlay(Capsule().strokeBorder(p.lineStrong, lineWidth: 1))
                    .contentShape(Capsule())
            }

            Text("\(selectedPhotos.count)")
                .font(DQFont.monoSized(13, .medium))
                .foregroundStyle(p.text3)
                .accessibilityLabel("\(selectedPhotos.count) photos selected")
        }
    }
}
