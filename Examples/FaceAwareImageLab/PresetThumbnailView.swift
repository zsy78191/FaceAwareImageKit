import SwiftUI

struct PresetThumbnailView: View {
    let url: URL
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    ProgressView()
                }
            }
        }
        .frame(width: 104, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(false)
        .task(id: url) {
            image = try? await PresetThumbnailPipeline.shared.load(url)
        }
    }
}
