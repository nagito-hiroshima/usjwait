import Foundation

struct Config {
    /// カタログAPIのURL
    static let masterURL = URL(string: "https://usjwait.moenaigomi.com/api/catalog")!

    /// 相対URL(`/api/...`) を解決するためのベースURL
    static var endpointBase: URL {
        // masterURL からスキームとホスト部分だけ取り出してベースを生成
        var comps = URLComponents(url: masterURL, resolvingAgainstBaseURL: false)!
        comps.path = "/"  // ルートパスに戻す
        comps.query = nil
        return comps.url!
    }
}
