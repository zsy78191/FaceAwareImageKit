import FaceAwareImageKit
import Foundation

enum FaceAwareImageSource: Identifiable {
    case remote(URL)
    case local(Data, name: String)

    var id: String {
        switch self {
        case .remote(let url): return "remote:\(url.absoluteString)"
        case .local(let data, let name): return "local:\(name):\(data.count):\(data.prefix(32).hashValue)"
        }
    }

    var label: String {
        switch self {
        case .remote(let url): return url.host() ?? url.absoluteString
        case .local(_, let name): return name
        }
    }
}

enum FaceAwareLoadState {
    case idle
    case loading
    case loaded(FaceAwareImageResource)
    case failed(String)
}
