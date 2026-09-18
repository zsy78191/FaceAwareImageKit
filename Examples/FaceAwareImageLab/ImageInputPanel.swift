import PhotosUI
import SwiftUI

struct ImageInputPanel: View {
    @Binding var urlText: String
    @Binding var selectedPhoto: PhotosPickerItem?
    let onLoadURL: () -> Void
    let onSelectPreset: (PresetImage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("输入图片 URL", text: $urlText).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).keyboardType(.URL)
                Button("加载", action: onLoadURL).buttonStyle(.borderedProminent)
            }
            HStack {
                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("选择相册图片", systemImage: "photo.on.rectangle") }.buttonStyle(.bordered)
                NavigationLink {
                    PresetImageListView(onSelect: onSelectPreset)
                } label: {
                    Label("在线预设图片", systemImage: "photo.stack")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
