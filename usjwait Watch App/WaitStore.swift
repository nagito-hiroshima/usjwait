import Foundation
import Combine

@MainActor
final class WaitStore: ObservableObject {
    @Published var masters: [AttractionMaster] = []
    @Published var attractions: [Attraction] = []
    @Published var lastFetch: Date? = nil
    @Published var errorMessage: String? = nil
    @Published var favorites: Set<String> = []
    @Published var sortAsc: Bool = true

    private var isLoading = false

    init() {
        if let cached = CacheStore.shared.load() {
            self.attractions = cached.attractions
            self.lastFetch = cached.fetchedAt
        }
        if let saved = UserDefaults.standard.array(forKey: "favorites") as? [String] {
            self.favorites = Set(saved)
        }
    }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
    }

    func loadMasterAndRefresh() async {
        self.masters = await MasterRepository.shared.load()
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var rows: [Attraction] = []

        await withTaskGroup(of: Attraction?.self) { group in
            for m in masters {
                group.addTask {
                    do {
                        let s = try await WaitAPI.shared.fetchStats(for: m)
                        return await MainActor.run { Attraction(stats: s, master: m) }
                    } catch {
                        return await MainActor.run { Attraction.placeholder(from: m) }
                    }
                }
            }
            for await maybe in group {
                if let a = maybe { rows.append(a) }
            }
        }

        rows.sort {
            let wa = $0.waitMinutes ?? Int.max
            let wb = $1.waitMinutes ?? Int.max
            return sortAsc ? (wa < wb) : (wa > wb)
        }

        self.attractions = rows
        let now = Date()
        self.lastFetch = now
        CacheStore.shared.save(APIResponse(attractions: rows, fetchedAt: now))
        self.errorMessage = rows.contains(where: { $0.waitMinutes != nil }) ? nil : "更新に失敗。前回値を表示中"
    }

    // 表示用（お気に入りフィルタ）
    func favoriteOnly(_ enabled: Bool) -> [Attraction] {
        guard enabled else { return attractions }
        return attractions.filter { favorites.contains($0.id) }
    }
}
