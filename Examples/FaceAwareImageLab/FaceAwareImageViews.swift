import FaceAwareImageKit
import SwiftUI

struct FaceAwareImageComparisonView: View {
    let resource: FaceAwareImageResource
    @State private var previewHeight: CGFloat = 180

    private let aspectPresets: [(String, CGFloat)] = [
        ("1:1", 1),
        ("4:3", 4.0 / 3.0),
        ("16:9", 16.0 / 9.0)
    ]

    private var analysis: FaceAwareImageAnalysis { resource.analysis }

    static func totalHeight(previewHeight: CGFloat) -> CGFloat {
        previewHeight * 2 + 260
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 16) {
                controls(containerWidth: proxy.size.width)

                let comparisonSize = CGSize(width: proxy.size.width, height: previewHeight)

                VStack(alignment: .leading, spacing: 8) {
                    Text("普通 Image · scaledToFill").font(.headline)
                    StandardImageView(image: resource.image, size: comparisonSize)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Face-aware · focal-point crop").font(.headline)
                    FaceAwareImage(resource: resource)
                        .frame(width: comparisonSize.width, height: comparisonSize.height)
                        .overlay(alignment: .bottom) {
                            Text("focal-point crop").font(.caption2.bold()).padding(6).background(.black.opacity(0.6)).foregroundStyle(.white)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("人脸数量：\(analysis.faceCount)")
                    Text("显著物体数量：\(analysis.salientObjectCount)")
                    Text("焦点来源：\(analysis.focusSource.displayName)")
                    Text("focal point：\(analysis.focalPoint.x, specifier: "%.2f"), \(analysis.focalPoint.y, specifier: "%.2f")")
                    Text(focusDescription)
                    Text("容器：\(Int(proxy.size.width)) × \(Int(previewHeight))")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                
                VStack {
                    
                }.padding()
            }
        }
        .frame(height: Self.totalHeight(previewHeight: previewHeight))
    }

    private var focusDescription: String {
        switch analysis.focusSource {
        case .face: return "使用面积前三人脸的加权中心"
        case .salientObject: return "未检测到人脸，使用主要物体焦点"
        case .imageCenter: return "未检测到主体，使用图片中心点"
        @unknown default: return "未知焦点来源"
        }
    }

    @ViewBuilder
    private func controls(containerWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("预览尺寸").font(.headline)
                Spacer()
                Text("\(Int(containerWidth)) × \(Int(previewHeight))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack {
                ForEach(aspectPresets, id: \.0) { title, ratio in
                    Button(title) {
                        previewHeight = min(360, max(80, containerWidth / ratio))
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack {
                Text("高度").font(.caption)
                Slider(value: $previewHeight, in: 60...360, step: 10)
                Text("\(Int(previewHeight))")
                    .font(.caption.monospaced())
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }
}

private extension FaceAwareFocusSource {
    /// Lab-side presentation label; the framework only publishes the stable cases.
    var displayName: String {
        switch self {
        case .face: return "face"
        case .salientObject: return "salient object"
        case .imageCenter: return "image center"
        @unknown default: return rawValue
        }
    }
}

private struct StandardImageView: View {
    let image: CGImage
    let size: CGSize

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(alignment: .bottom) { Text("scaledToFill").font(.caption2.bold()).padding(6).background(.black.opacity(0.6)).foregroundStyle(.white) }
            .allowsHitTesting(false)
    }
}
