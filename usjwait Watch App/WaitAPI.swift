import Foundation

final class WaitAPI {
    static let shared = WaitAPI()
    private init() {}

    private static let dec: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func fetchStats(for master: AttractionMaster) async throws -> AttractionStats {
        guard let url = URL(string: master.endpoint) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        if let single = try? Self.dec.decode(AttractionStats.self, from: data) { return single }
        if let list = try? Self.dec.decode([AttractionStats].self, from: data), let first = list.first { return first }
        throw URLError(.cannotDecodeContentData)
    }
}
