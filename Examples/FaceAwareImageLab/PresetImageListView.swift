import SwiftUI

struct PresetImageListView: View {
    let onSelect: (PresetImage) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(PresetImageCategory.allCases, id: \.self) { category in
                Section(category.title) {
                    ForEach(PresetImageCatalog.all.filter { $0.category == category }) { preset in
                        Button {
                            onSelect(preset)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                PresetThumbnailView(url: preset.thumbnailURL)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(preset.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(preset.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("在线预设图片")
        .navigationBarTitleDisplayMode(.inline)
    }
}
