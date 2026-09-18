import Foundation

enum PresetImageCategory: String, CaseIterable, Hashable, Sendable {
    case people
    case animal
    case object

    var title: String {
        switch self {
        case .people: return "人物"
        case .animal: return "动物"
        case .object: return "物品与场景"
        }
    }
}

struct PresetImage: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let category: PresetImageCategory
    let thumbnailURL: URL
    let imageURL: URL
}

enum PresetImageCatalog {
    static let all: [PresetImage] = [
        preset("portrait-woman", "单人肖像", "验证单张人脸定位", .people, "photo-1494790108377-be9c29b29330"),
        preset("portrait-woman-side", "侧位肖像", "验证偏离中心的人脸", .people, "photo-1534528741775-53994a69daeb"),
        preset("portrait-man", "男性肖像", "验证不同人脸比例", .people, "photo-1500648767791-00dcc994a43e"),
        preset("group", "多人合照", "验证前三人脸加权中心", .people, "photo-1529156069898-49953e39b3ac"),
        preset("cat", "猫咪", "无人脸时使用显著物体", .animal, "photo-1574158622682-e40e69881006"),
        preset("camera", "相机", "验证主要物品定位", .object, "photo-1516035069371-29a1b244cc32"),
        preset("food", "食物", "验证复杂主体区域", .object, "photo-1546069901-ba9599a7e63c")
    ]

    static let defaultPreset = all[0]

    private static func preset(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ category: PresetImageCategory,
        _ unsplashID: String
    ) -> PresetImage {
        let base = "https://images.unsplash.com/\(unsplashID)"
        return PresetImage(
            id: id,
            title: title,
            subtitle: subtitle,
            category: category,
            thumbnailURL: URL(string: "\(base)?w=320&h=220&fit=crop&q=72")!,
            imageURL: URL(string: "\(base)?w=1600&q=85")!
        )
    }
}
