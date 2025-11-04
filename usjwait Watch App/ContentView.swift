import SwiftUI
#if os(watchOS)
import WatchKit
#endif

// 名前表示モード
private enum NameMode { case short, code }

struct ContentView: View {
    @StateObject private var store = WaitStore()
    @State private var showFavoritesOnly = false
    @State private var nameMode: NameMode = .short  // 初期は略称

    var body: some View {
        NavigationStack {
            List {
                let rows = store.favoriteOnly(showFavoritesOnly)

                // 絞り込み0件のときの案内
                if showFavoritesOnly && rows.isEmpty {
                    EmptyFavoritesRow()
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                ForEach(rows) { a in
                    AttractionRow(
                        attraction: a,
                        nameMode: nameMode,
                        isFav: store.favorites.contains(a.id),
                        onToggleFav: { store.toggleFavorite(a.id) }
                    )
                }

                // リスト末尾に更新情報（固定フッターではなくスクロール時だけ見える）
                FooterStatusRow(lastFetch: store.lastFetch, errorMessage: store.errorMessage)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 16, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .navigationTitle("USJ 待ち時間")
            .toolbar {
                // ★：タップ=絞り込み、長押し=CODE/略称切替（ハプティック付き）
                ToolbarItem(placement: .topBarLeading) {
                    FavToolbarButton(
                        showFavoritesOnly: $showFavoritesOnly,
                        nameMode: $nameMode
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.sortAsc.toggle()
                        Task { await store.refresh() }
                    } label: { Image(systemName: store.sortAsc ? "arrow.up" : "arrow.down") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await store.loadMasterAndRefresh() }
        }
    }
}

// MARK: - ★ツールバー（タップ＆長押し）
private struct FavToolbarButton: View {
    @Binding var showFavoritesOnly: Bool
    @Binding var nameMode: NameMode

    var body: some View {
        Image(systemName: showFavoritesOnly ? "star.fill" : "star")
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                showFavoritesOnly.toggle()
                haptic(.click)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    nameMode = (nameMode == .short) ? .code : .short
                    haptic(.success)
                }
            )
            .accessibilityLabel("お気に入り/コード切替")
    }

    private func haptic(_ type: WKHapticType) {
        #if os(watchOS)
        WKInterfaceDevice.current().play(type)
        #endif
    }
}

// MARK: - お気に入り未登録プレースホルダ
private struct EmptyFavoritesRow: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("お気に入りが未登録です")
                .font(.footnote).bold()
            Text("各行の右の ★ をタップして追加してください")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }
}

// MARK: - リスト末尾の更新情報
private struct FooterStatusRow: View {
    let lastFetch: Date?
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 6) {
            Divider()
            if let ts = lastFetch {
                Text("最終更新: \(ts.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if let err = errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }
}

// MARK: - 行（CODEモードは画像/正式名/エリアを非表示）
private struct AttractionRow: View {
    let attraction: Attraction
    let nameMode: NameMode
    let isFav: Bool
    let onToggleFav: () -> Void
    @State private var expanded = false

    private var titleText: String {
        switch nameMode {
        case .short: return attraction.shortName
        case .code:  return (attraction.codeName?.isEmpty == false) ? attraction.codeName! : attraction.shortName
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { expanded.toggle() } label: {
                VStack(alignment: .leading, spacing: 6) {
                    // 1段目：タイトル（略称/コード）＋ 待ち時間
                    HStack(spacing: 6) {
                        Text(titleText).font(.headline).bold().lineLimit(1)
                        Spacer(minLength: 0)
                        Text(waitText).font(.callout).bold()
                    }

                    if expanded {
                        // CODEモードでは画像/正式名/エリアを出さない
                        if nameMode == .short {
                            HStack(alignment: .top, spacing: 8) {
                                if let urlString = attraction.imageURL,
                                   let url = URL(string: urlString) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView().frame(width: 40, height: 40)
                                        case .success(let image):
                                            image.resizable()
                                                 .scaledToFill()
                                                 .frame(width: 40, height: 40)
                                                 .clipShape(RoundedRectangle(cornerRadius: 8))
                                        case .failure:
                                            MonogramIcon(text: attraction.shortName)
                                        @unknown default:
                                            MonogramIcon(text: attraction.shortName)
                                        }
                                    }
                                } else {
                                    MonogramIcon(text: attraction.shortName)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attraction.name)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    if let area = attraction.area, !area.isEmpty {
                                        Text(area)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }

                        // 最高・最低・平均（平均は updatedText を併記）
                        StatsRow(attraction: attraction)
                    }
                }
            }
            .buttonStyle(.plain)

            // お気に入りトグル
            Button(action: onToggleFav) {
                Image(systemName: isFav ? "star.fill" : "star")
            }
            .buttonStyle(.plain)
        }
    }

    private var waitText: String {
        if let w = attraction.waitMinutes { return "\(w)分" }
        return "--"
    }
}

// MARK: - 統計行（平均の右に API の updated を表示）
private struct StatsRow: View {
    let attraction: Attraction
    private var avgDisplay: Int? { attraction.avgToday ?? attraction.median }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("最低").font(.caption2).foregroundStyle(.secondary)
                Text(minText).font(.caption).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("最高").font(.caption2).foregroundStyle(.secondary)
                Text(maxText).font(.caption).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("平均").font(.caption2).foregroundStyle(.secondary)
                Text(avgWithTimeText).font(.caption).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }

    private var minText: String {
        if let v = attraction.min {
            if let t = attraction.minTime, !t.isEmpty { return "\(v)分 (\(t))" }
            return "\(v)分"
        }
        return "--"
    }

    private var maxText: String {
        if let v = attraction.max {
            if let t = attraction.maxTime, !t.isEmpty { return "\(v)分 (\(t))" }
            return "\(v)分"
        }
        return "--"
    }

    private var avgWithTimeText: String {
        guard let v = avgDisplay else { return "--" }
        if let t = attraction.updatedText, !t.isEmpty {
            return "\(v)分 (\(t))"   // APIの updated を優先
        }
        if let d = attraction.lastUpdated {
            let time = d.formatted(date: .omitted, time: .shortened)
            return "\(v)分 (\(time))"
        }
        return "\(v)分"
    }
}

// MARK: - 画像が無い/失敗時の簡易アイコン
private struct MonogramIcon: View {
    let text: String
    var body: some View {
        ZStack {
            Circle().fill(.gray.opacity(0.2))
            Text(String(text.prefix(2))).font(.caption).bold()
        }
        .frame(width: 40, height: 40)
    }
}


#Preview {
    ContentView()
}
