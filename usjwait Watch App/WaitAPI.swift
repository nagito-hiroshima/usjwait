import Foundation

actor WaitAPI {
    static let shared = WaitAPI()
    private init() {}

    // ========= ISO8601 decoder（小数秒あり/なし） =========
    nonisolated static func makeISO8601Decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let dt = f1.date(from: s) { return dt }
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let dt = f2.date(from: s) { return dt }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Invalid ISO8601: \(s)"))
        }
        return d
    }

    // ========= 相対/絶対 endpoint を確実に解決 =========
    nonisolated private static func resolveEndpoint(_ endpoint: String) -> URL? {
        // 1) すでに絶対URLならそのまま
        if let u = URL(string: endpoint), u.scheme != nil { return u }

        // 2) 文字列連結で確実に絶対化（watchOS の relativeTo 問題回避）
        //    Config.endpointBase は https://usjwait.moenaigomi.com などドメインルート
        let baseStr = Config.endpointBase.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let epStr   = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let epNoSlash = epStr.hasPrefix("/") ? String(epStr.dropFirst()) : epStr
        let finalStr  = baseStr + "/" + epNoSlash  // 例: https://host/api/wait?slug=...

        return URL(string: finalStr)
    }

    // ========= API =========
    func fetchStats(for master: AttractionMaster) async throws -> AttractionStats {
        guard let url0 = Self.resolveEndpoint(master.endpoint) else { throw URLError(.badURL) }

        // _ts を付けて最終URLを構築
        var comps = URLComponents(url: url0, resolvingAgainstBaseURL: false)!
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "_ts", value: String(Int(Date().timeIntervalSince1970))))
        comps.queryItems = items

        guard let url = comps.url else { throw URLError(.badURL) }

        // 叩くURLをログ
        print("➡️ Fetch: \(url.absoluteString)")

        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        //saveDebugJSON(data, name: master.codeName ?? master.id)

        let decoder = Self.makeISO8601Decoder()
        let stats: AttractionStats = try await MainActor.run {
            try decoder.decode(AttractionStats.self, from: data)
        }

        let currentStr = stats.current.map { "\($0)分" } ?? "--"
        let medianStr  = stats.median.map { "\($0)分" } ?? "--"
        let scrapedStr = Self.formatDate(stats.scraped_at)
        let updatedStr = stats.updated ?? "--"
        print("✅ [\(master.shortName)] 現在: \(currentStr) / 中央: \(medianStr) / 平均更新時刻: \(updatedStr) / 取得: \(scrapedStr)")

        return stats
    }

    // ========= Debug 保存 & 日付整形 =========
//    nonisolated private func saveDebugJSON(_ data: Data, name: String) {
//        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//        let url = dir.appendingPathComponent("debug_\(name).json")
//        do { try data.write(to: url); print("🗂 Saved debug: \(url.path)") }
//        catch { print("⚠️ Save debug failed: \(error.localizedDescription)") }
//    }

    nonisolated private static func formatDate(_ date: Date?) -> String {
        guard let d = date else { return "--" }
        if #available(watchOS 10.0, *) { return d.formatted(date: .numeric, time: .shortened) }
        let f = DateFormatter(); f.locale = .init(identifier: "ja_JP"); f.dateFormat = "yyyy/MM/dd HH:mm"
        return f.string(from: d)
    }
}
