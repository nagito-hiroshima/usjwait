import Foundation

final class MasterRepository {
    static let shared = MasterRepository()
    private init() {}

    private let cacheKey = "attractions_master_cache"
    private let etagKey  = "attractions_master_etag"

    /// マスタをロード（キャッシュ → リモート → フォールバック）
    func load() async -> [AttractionMaster] {
        if let cached = loadFromCache() { return cached }
        if let remote = try? await loadFromRemote() { return remote }
        // 最小フォールバック（1件でも表示できる）
        return [
            AttractionMaster(
                id: "spyxr",
                displayName: "SPY×FAMILY XRライド",
                shortName: "XRライド",
                codeName: "SPY",
                apiTitle: "ev_spy_family_xr",
                endpoint: "https://usjwait.moenaigomi.com/api/wait?slug=ev_spy_family_xr",
                imageURL: "https://www.usj.co.jp/tridiondata/usj/ja/jp/files/images/gds-images/usj-gds-spy-family-2025-b.jpg",
                area: "ハリウッド・エリア",
                active: true
            )
        ]
    }

    // MARK: - Private

    private func loadFromCache() -> [AttractionMaster]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let file = try? d.decode(AttractionMasterFile.self, from: data) else { return nil }
        return file.items.filter { $0.active ?? true }
    }

    private func loadFromRemote() async throws -> [AttractionMaster] {
        var req = URLRequest(url: Config.masterURL) // ← Config.masterURL はプロジェクト側で定義
        if let etag = UserDefaults.standard.string(forKey: etagKey) {
            req.addValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if http.statusCode == 304, let cached = loadFromCache() {
            return cached
        }
        guard 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }

        // 受信データをデコード
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let file = try d.decode(AttractionMasterFile.self, from: data)

        // 生データをキャッシュに保存
        UserDefaults.standard.set(data, forKey: cacheKey)
        if let et = http.value(forHTTPHeaderField: "ETag") {
            UserDefaults.standard.set(et, forKey: etagKey)
        }
        return file.items.filter { $0.active ?? true }
    }
}
