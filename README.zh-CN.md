# FaceAwareImageKit

**简体中文** | [English](README.md)

> 始终将人脸保持在画面内的 Aspect-fill SwiftUI 图片组件。

FaceAwareImageKit 加载远程图片，通过设备端 Vision 分析定位人脸和显著对象，并在渲染时保持焦点区域可见，即使布局的宽高比原本会裁剪掉人脸，也能正确显示。

- ✅ 纯 SwiftUI 视图（`FaceAwareImage`、`FaceAwareAsyncImage`）。
- ✅ 支持 async/await 的图片处理管线，包含请求去重和基于 generation 的取消机制。
- ✅ 有容量限制的 HTTP 缓存和解码图片缓存。
- ✅ 基于 `actor` 隔离的客户端，可以安全地在多个视图之间共享。
- ✅ 支持 iOS 15+、macOS 13+、visionOS 1+，零第三方依赖。

## 系统要求

| 平台 | 最低版本 |
|------|----------|
| iOS | 15.0 |
| iPadOS | 15.0 |
| macOS | 13.0 |
| visionOS | 1.0 |

Swift 5.9 / Xcode 15 或更高版本。

## 安装

### Swift Package Manager

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/<your-org>/FaceAwareImageKit.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "FaceAwareImageKit", package: "FaceAwareImageKit"),
        ]
    )
]
```

也可以在 Xcode 中选择 **File → Add Packages…**，然后粘贴仓库地址。

## 快速开始

```swift
import FaceAwareImageKit
import SwiftUI

struct AvatarView: View {
    let url: URL

    var body: some View {
        FaceAwareAsyncImage(url: url)
            .frame(width: 96, height: 96)
            .clipShape(Circle())
    }
}
```

对于已经解码的资源或自定义加载阶段，可以这样使用：

```swift
FaceAwareImage(resource: resource)            // resource: FaceAwareImageResource
FaceAwareAsyncImage(url: url) { phase in       // phase: FaceAwareImagePhase
    switch phase {
    case .empty:        ProgressView()
    case .progress(let p): ProgressView(value: p)
    case .success(let res, let frame): res.image.resizable().aspectRatio(contentMode: .fill)
    case .failure:      Image(systemName: "photo")
    }
}
```

## 示例

示例应用 Image Lab 对比了普通的 `scaledToFill` 渲染和基于人脸焦点的裁剪效果。在相同宽高比下进行裁剪时，FaceAwareImageKit 会尽量保持主体位于可见区域内。

<p align="center">
  <img src="docs/images/face-aware-example-man.png" alt="人脸感知裁剪示例：男性人像" width="320" />
  <img src="docs/images/face-aware-example-woman.png" alt="人脸感知裁剪示例：女性人像" width="320" />
</p>

## 配置

建议在应用启动时创建一次客户端，并将其传给视图，不要在 `body` 中创建客户端。

```swift
let client = FaceAwareImageClient(configuration: .init(
    memoryCacheBytesLimit: 32 * 1024 * 1024,
    preferredImageDimension: 1024,
))

FaceAwareAsyncImage(url: avatarURL, client: client)
```

## 示例应用

仓库在 `Examples/FaceAwareImageLab` 中包含一个 SwiftUI 示例应用。使用以下命令生成 Xcode 工程：

```bash
cd Examples
xcodegen generate
open FaceAwareImageKitExamples.xcodeproj
```

## 文档

DocC 文档位于 `Sources/FaceAwareImageKit/Documentation.docc`。可以使用以下命令在本地构建并预览：

```bash
swift build
xcrun docc preview --path .build/debug/FaceAwareImageKit.docc
```

## 许可证

MIT，详见 [`LICENSE`](LICENSE)。

## 参与贡献

欢迎提交 Issue 和 Pull Request。提交前请运行 `swift test` 和 `swift build`。
