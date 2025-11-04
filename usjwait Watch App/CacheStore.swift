import Foundation

final class CacheStore {
    static let shared = CacheStore()
    private init() {}

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("wait_cache.json")
    }

    func save(_ response: APIResponse) {
        if let data = try? JSONEncoder().encode(response) {
            // options は省略（デフォルトで十分）
            try? data.write(to: cacheURL)
        }
    }

    func load() -> APIResponse? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(APIResponse.self, from: data)
    }
}
