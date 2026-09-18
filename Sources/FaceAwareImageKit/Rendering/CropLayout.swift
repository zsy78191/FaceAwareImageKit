import CoreGraphics

struct CropLayout: Equatable {
    let renderedSize: CGSize
    let offset: CGPoint

    init(imageSize: CGSize, containerSize: CGSize, focalPoint: CGPoint) {
        precondition(imageSize.width > 0 && imageSize.height > 0, "imageSize must have positive dimensions")

        if containerSize == .zero {
            renderedSize = .zero
            offset = .zero
            return
        }

        let scale = max(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let rendered = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let overflow = CGSize(
            width: rendered.width - containerSize.width,
            height: rendered.height - containerSize.height
        )
        let desiredX = containerSize.width / 2 - focalPoint.x * rendered.width
        let desiredY = containerSize.height / 2 - focalPoint.y * rendered.height

        renderedSize = rendered
        offset = CGPoint(
            x: min(0, max(-overflow.width, desiredX)),
            y: min(0, max(-overflow.height, desiredY))
        )
    }
}
