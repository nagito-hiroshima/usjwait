import Foundation

// ===== 外部マスタ（catalog JSON） =====
struct AttractionMasterFile: Codable {
    let version: Int
    let generated_at: Date?
    let items: [AttractionMaster]

    // 二重ラップ { items: [...] } に対応するための薄いラッパ
    private struct ItemsWrapper: Codable {
        let items: [AttractionMaster]
    }

    enum CodingKeys: String, CodingKey {
        case version
        case generated_at
        case items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decode(Int.self, forKey: .version)
        self.generated_at = try? c.decode(Date.self, forKey: .generated_at)

        // まずは items を直接の配列として読む
        if let direct = try? c.decode([AttractionMaster].self, forKey: .items) {
            self.items = direct
            return
        }
        // ダメなら { items: [...] } のラッパとして読む
        if let wrapped = try? c.decode(ItemsWrapper.self, forKey: .items) {
            self.items = wrapped.items
            return
        }

        // どちらでもなければエラー
        throw DecodingError.dataCorrupted(
            .init(codingPath: [CodingKeys.items],
                  debugDescription: "items は配列または {items:[...]} である必要があります")
        )
    }
}

struct AttractionMaster: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let shortName: String
    let codeName: String?       // CODE表示用
    let apiTitle: String
    let endpoint: String
    let imageURL: String?
    let area: String?
    let active: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, displayName, shortName, codeName, apiTitle, endpoint, area, active
        case imageURL = "image_url" // image_url → imageURL
    }
}

// ===== /api/wait のレスポンス想定 =====
struct AttractionStats: Decodable, Hashable {
    let attraction: String
    let current: Int?
    let avg_today: Int?
    let median: Int?
    let min: Int?
    let min_time: String?
    let max: Int?
    let max_time: String?
    let avg_week: Int?
    let avg_month: Int?
    let updated: String?        // 平均の横に出す表示用時刻（例 "22:00"）
    let scraped_at: Date?       // 実際の取得日時
    let source: String?
}

// ===== 画面表示用 =====
struct Attraction: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let shortName: String
    let codeName: String?
    let waitMinutes: Int?
    let status: String?
    let area: String?
    let lastUpdated: Date?      // scraped_at
    let updatedText: String?    // updated（平均の横に出す）

    // 統計
    let median: Int?
    let min: Int?
    let minTime: String?
    let max: Int?
    let maxTime: String?
    let avgToday: Int?
    let avgWeek: Int?
    let avgMonth: Int?

    let imageURL: String?

    // 明示イニシャライザ（placeholder などで使用）
    init(
        id: String,
        name: String,
        shortName: String,
        codeName: String?,
        waitMinutes: Int?,
        status: String?,
        area: String?,
        lastUpdated: Date?,
        updatedText: String?,
        median: Int?,
        min: Int?,
        minTime: String?,
        max: Int?,
        maxTime: String?,
        avgToday: Int?,
        avgWeek: Int?,
        avgMonth: Int?,
        imageURL: String?
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.codeName = codeName
        self.waitMinutes = waitMinutes
        self.status = status
        self.area = area
        self.lastUpdated = lastUpdated
        self.updatedText = updatedText
        self.median = median
        self.min = min
        self.minTime = minTime
        self.max = max
        self.maxTime = maxTime
        self.avgToday = avgToday
        self.avgWeek = avgWeek
        self.avgMonth = avgMonth
        self.imageURL = imageURL
    }

    // stats + master から合成
    init(stats s: AttractionStats, master: AttractionMaster) {
        self.init(
            id: master.id,
            name: master.displayName,
            shortName: master.shortName,
            codeName: master.codeName,
            waitMinutes: s.current,
            status: (s.current == nil) ? "UNKNOWN" : "OPERATING",
            area: master.area,
            lastUpdated: s.scraped_at,
            updatedText: s.updated,
            median: s.median,
            min: s.min,
            minTime: s.min_time,
            max: s.max,
            maxTime: s.max_time,
            avgToday: s.avg_today,
            avgWeek: s.avg_week,
            avgMonth: s.avg_month,
            imageURL: master.imageURL
        )
    }

    // ネットワーク失敗時のプレースホルダ
    static func placeholder(from master: AttractionMaster) -> Attraction {
        Attraction(
            id: master.id,
            name: master.displayName,
            shortName: master.shortName,
            codeName: master.codeName,
            waitMinutes: nil,
            status: "UNKNOWN",
            area: master.area,
            lastUpdated: nil,
            updatedText: nil,
            median: nil,
            min: nil,
            minTime: nil,
            max: nil,
            maxTime: nil,
            avgToday: nil,
            avgWeek: nil,
            avgMonth: nil,
            imageURL: master.imageURL
        )
    }
}

// ===== キャッシュ保存 =====
struct APIResponse: Codable {
    let attractions: [Attraction]
    let fetchedAt: Date
}
