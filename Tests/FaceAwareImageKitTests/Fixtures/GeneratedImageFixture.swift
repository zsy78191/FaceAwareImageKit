import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum GeneratedImageFixture {
    static func makeImage(width: Int = 2_400, height: Int = 1_600) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw GeneratedImageFixtureError.contextCreationFailed
        }

        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw GeneratedImageFixtureError.imageCreationFailed
        }
        return image
    }

    static func makePNGData(width: Int = 2_400, height: Int = 1_600) throws -> Data {
        let image = try makeImage(width: width, height: height)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw GeneratedImageFixtureError.destinationCreationFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw GeneratedImageFixtureError.encodingFailed
        }
        return data as Data
    }
}

private enum GeneratedImageFixtureError: Error {
    case contextCreationFailed
    case imageCreationFailed
    case destinationCreationFailed
    case encodingFailed
}
