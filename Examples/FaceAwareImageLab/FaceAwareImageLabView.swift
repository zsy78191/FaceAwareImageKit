import FaceAwareImageKit
import PhotosUI
import SwiftUI

struct FaceAwareImageLabView: View {
    /// Retained for the lifetime of the Lab so every URL load, local analysis, and
    /// preset reload shares one client's decoded-resource and HTTP caches.
    private static let client = FaceAwareImageClient()

    @State private var urlText: String
    @State private var source: FaceAwareImageSource
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loadState: FaceAwareLoadState = .idle

    init() {
        let url = PresetImageCatalog.defaultPreset.imageURL
        _source = State(initialValue: .remote(url))
        _urlText = State(initialValue: url.absoluteString)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Face-aware Cover").font(.largeTitle.bold())
                    Text("比较普通 Image 和人脸感知 Cover 裁剪。支持 Web URL 与相册图片。").foregroundStyle(.secondary)
                    ImageInputPanel(
                        urlText: $urlText,
                        selectedPhoto: $selectedPhoto,
                        onLoadURL: loadURL,
                        onSelectPreset: selectPreset
                    )
                    content
                }
                .padding()
            }
            .navigationTitle("Image Lab")
        }
        .task(id: source.id) { await load(source) }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                source = .local(data, name: "PhotosPicker image")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch loadState {
        case .idle: ContentUnavailableView("请选择图片", systemImage: "photo.on.rectangle")
        case .loading: ProgressView("正在下载和检测…").frame(maxWidth: .infinity, minHeight: 240)
        case .failed(let message): ContentUnavailableView("图片加载失败", systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded(let resource): FaceAwareImageComparisonView(resource: resource)
        }
    }

    private func loadURL() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "http" || url.scheme == "https" else { return }
        source = .remote(url)
    }

    private func selectPreset(_ preset: PresetImage) {
        urlText = preset.imageURL.absoluteString
        source = .remote(preset.imageURL)
    }

    private func load(_ source: FaceAwareImageSource) async {
        loadState = .loading
        do {
            let resource: FaceAwareImageResource
            switch source {
            case .remote(let url):
                resource = try await Self.client.load(url: url)
            case .local(let data, _):
                resource = try await Self.client.analyze(data: data)
            }
            // `.task(id: source.id)` cancels the previous load on every source switch,
            // and a stale task can still finish. Only the current source may publish.
            guard source.id == self.source.id else { return }
            loadState = .loaded(resource)
        } catch FaceAwareImageError.cancelled {
            // Cancellation is expected while switching sources; it is not a failure.
        } catch {
            guard source.id == self.source.id else { return }
            loadState = .failed(error.localizedDescription)
        }
    }
}
