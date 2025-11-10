import Foundation

final class MasterRepository {
    static let shared = MasterRepository()
    private init() {}

    private let cacheKey = "attractions_master_cache"
    private let etagKey  = "attractions_master_etag"

    // MARK: - Public

    /// マスタをロード
    /// - Parameter force: true のときはキャッシュがあっても必ずリモート確認（If-None-Match）を行う
    func load(force: Bool = false) async -> [AttractionMaster] {
        print("📦 [MasterRepository] load(force: \(force)) 開始")

        // force=false はキャッシュ優先
        if !force, let cached = loadFromCache() {
            print("💾 キャッシュを使用 (\(cached.count) 件)")
            return cached
        }

        do {
            let remote = try await loadFromRemoteConditional()
            print("🌐 リモートから取得成功 (\(remote.count) 件)")
            return remote
        } catch {
            print("⚠️ リモート取得エラー: \(error.localizedDescription)")
        }

        // リモート失敗時はキャッシュ → 最小フォールバック
        if let cached = loadFromCache() {
            print("💾 フォールバック: キャッシュを使用")
            return cached
        }

        print("🪫 キャッシュなし → 最小フォールバックを使用")
        return minimalFallback()
    }

    /// マスタキャッシュとETagを削除
    func clearCache() {
        print("🧹 キャッシュ削除")
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: etagKey)
    }

    // MARK: - Private

    private func loadFromCache() -> [AttractionMaster]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            print("💾 キャッシュなし")
            return nil
        }

        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .useDefaultKeys // モデル側がsnakeを含むため

        do {
            let file = try d.decode(AttractionMasterFile.self, from: data)
            print("💾 キャッシュ読み込み成功 (\(file.items.count) 件)")
            return file.items.filter { $0.active ?? true }
        } catch {
            print("💥 キャッシュデコード失敗: \(error.localizedDescription)")
            return nil
        }
    }

    /// ETag を使った条件付きGET。304ならキャッシュを返す。
    private func loadFromRemoteConditional() async throws -> [AttractionMaster] {
        var req = URLRequest(url: Config.masterURL)
        if let etag = UserDefaults.standard.string(forKey: etagKey) {
            req.addValue(etag, forHTTPHeaderField: "If-None-Match")
            print("🪶 ETag 付きリクエスト: \(etag)")
        } else {
            print("🆕 初回リクエスト（ETagなし）")
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        print("📡 Status: \(http.statusCode)")
        print("🧾 Headers: \(http.allHeaderFields)")

        switch http.statusCode {
        case 304:
            print("✅ 304 Not Modified → キャッシュ使用")
            if let cached = loadFromCache() { return cached }

        case 200..<300:
            print("✅ 2xx（\(data.count) bytes）")

            // デコード（寛容）
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            d.keyDecodingStrategy = .useDefaultKeys // snakeはそのまま

            do {
                let file = try d.decode(AttractionMasterFile.self, from: data)

                // キャッシュ保存
                UserDefaults.standard.set(data, forKey: cacheKey)
                if let et = http.value(forHTTPHeaderField: "ETag") {
                    UserDefaults.standard.set(et, forKey: etagKey)
                    print("📎 ETag 保存: \(et)")
                }

                if let first = file.items.first {
                    print("🎢 先頭: \(first.displayName) [id=\(first.id)] active=\(String(describing: first.active))")
                }
                return file.items.filter { $0.active ?? true }

            } catch {
                // 失敗詳細を補足出力
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("🔎 Top-level keys: \(obj.keys.sorted())")
                    if let items = obj["items"] as? [String: Any],
                       let inner = items["items"] as? [[String: Any]],
                       let first = inner.first {
                        print("🔎 items.items[0] keys: \(first.keys.sorted())")
                    }
                } else if let text = String(data: data, encoding: .utf8) {
                    print("🔎 Body preview (utf8):\n\(text.prefix(1000))")
                }
                print("💥 JSONデコード失敗: \(error.localizedDescription)")
                throw error
            }

        default:
            print("❌ 非2xx: \(http.statusCode)")
            if let text = String(data: data, encoding: .utf8) {
                print("🪪 Body preview:\n\(text.prefix(1000))")
            }
            throw URLError(.badServerResponse)
        }

        // 稀ケース
        if let cached = loadFromCache() { return cached }
        print("🪫 キャッシュ無し → minimalFallback")
        return minimalFallback()
    }

    /// ネットもキャッシュも無いときの最小フォールバック
    private func minimalFallback() -> [AttractionMaster] {
        print("🧩 minimalFallback 使用")
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
}
