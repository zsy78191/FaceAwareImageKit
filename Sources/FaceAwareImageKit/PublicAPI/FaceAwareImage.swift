import CoreGraphics
import SwiftUI

/// Renders an already loaded resource with focal-point aware aspect fill.
///
/// The view always behaves like `aspect fill`: it scales the image until it covers its
/// container, positions it so the resource's focal point stays visible, and clips whatever
/// falls outside its bounds. Control the final size with ordinary frame or aspect-ratio
/// modifiers.
///
/// The view only derives crop geometry from its container size, so resizing it never
/// downloads, decodes, or analyzes anything.
///
/// The image is decorative: it carries no accessibility label of its own and disables hit
/// testing, so it never intercepts touches intended for surrounding controls.
public struct FaceAwareImage: View {
    private let resource: FaceAwareImageResource

    /// Creates a view that renders `resource`.
    ///
    /// - Parameter resource: A resource produced by ``FaceAwareImageClient``.
    public init(resource: FaceAwareImageResource) {
        self.resource = resource
    }

    /// The aspect-filled, clipped image.
    public var body: some View {
        GeometryReader { geometry in
            let layout = CropLayout(
                imageSize: resource.pixelSize,
                containerSize: geometry.size,
                focalPoint: resource.analysis.focalPoint
            )
            // Draw the image at exactly the computed fill size, then pin it to the
            // container's top-leading corner and shift it by the focal-point offset
            // that `CropLayout` already clamped.
            Image(decorative: resource.image, scale: 1)
                .resizable()
                .frame(width: layout.renderedSize.width, height: layout.renderedSize.height)
                .offset(x: layout.offset.x, y: layout.offset.y)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
