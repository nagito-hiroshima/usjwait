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
                // 並び替え
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.sortAsc.toggle()
                        Task { await store.refresh() }
                    } label: { Image(systemName: store.sortAsc ? "arrow.up" : "arrow.down") }
                }
                // 手動更新
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.refresh(includeCatalog: true) } } label: {
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
            Text("お気に入りが未登録です").font(.footnote).bold()
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

// MARK: - 行（開いたら★を消してスペースを開放 / CODEモードは画像等を非表示）
// MARK: - 行（右スワイプでお気に入りトグル / 色で状態を表示）
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
        VStack(alignment: .leading, spacing: 8) {
            // 1段目：タイトル＋待ち時間
            HStack(spacing: 6) {
                Text(titleText)
                    .font(.headline)
                    .bold()
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                Text(waitText)
                    .font(.callout)
                    .bold()
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if expanded {
                if nameMode == .short {
                    HStack(alignment: .center, spacing: 8) {
                        if let urlString = attraction.imageURL,
                           let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView().frame(width: 44, height: 44)
                                case .success(let image):
                                    image.resizable()
                                         .scaledToFill()
                                         .frame(width: 44, height: 44)
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
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }

                CompactStatsRow(attraction: attraction)
                    .padding(.trailing, 2)
                    .padding(.bottom, -2)
            }
        }
        .contentShape(Rectangle())
        .padding(8)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        }
        // AttractionRow の .background(...) を置き換え
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isFav
                      ? Color.yellow.opacity(0.2)                  // ← お気に入り時
                      : Color.black.opacity(0.00))
        )

        .modifier(FavSwipeModifier(isFav: isFav, onToggleFav: onToggleFav))
        .contextMenu {
            Button {
                onToggleFav()
                haptic(.success)
            } label: {
                Label(isFav ? "お気に入りを外す" : "お気に入りに追加",
                      systemImage: isFav ? "star.slash" : "star")
            }
        }
    }




    private var waitText: String {
        if let w = attraction.waitMinutes { return "\(w)分" }
        return "--"
    }

    private func haptic(_ type: WKHapticType) {
        #if os(watchOS)
        WKInterfaceDevice.current().play(type)
        #endif
    }
}

// MARK: - スワイプアクション共通部品
private struct FavSwipeModifier: ViewModifier {
    let isFav: Bool
    let onToggleFav: () -> Void

    func body(content: Content) -> some View {
        if #available(watchOS 10.0, *) {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        onToggleFav()
                        #if os(watchOS)
                        WKInterfaceDevice.current().play(.success)
                        #endif
                    } label: {
                        Label(isFav ? "外す" : "追加",
                              systemImage: isFav ? "star.slash" : "star")
                    }
                    .tint(.yellow)
                }
        } else {
            content // watchOS 9以下はcontextMenuのみ（上で用意済み）
        }
    }
}

// MARK: - コンパクト統計カード行（値と時刻を分離して2行に）
// MARK: - コンパクト統計カード行（SE対策：自動で2段にフォールバック）
private struct CompactStatsRow: View {
    let attraction: Attraction
    @Environment(\.dynamicTypeSize) private var typeSize

    private var avgDisplay: Int? { attraction.avgToday ?? attraction.median }

    var body: some View {
        Group {
            if #available(watchOS 10.0, *) {
                // 横3枚が入らなければ、2段（2+1）に自動で切替
                ViewThatFits(in: .horizontal) {
                    // 1) 通常：横3枚
                    HStack(spacing: 6) {
                        cardMin(compact: false)
                        cardMax(compact: false)
                        cardAvg(compact: false)
                    }
                    // 2) フォールバック：上2枚＋下1枚（コンパクト表示）
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            cardMin(compact: true)
                            cardMax(compact: true)
                        }
                        cardAvg(compact: true)
                    }
                }
            } else {
                // watchOS 9系など：幅が狭い/アクセシビリティ文字なら2段に
                GeometryReader { geo in
                    let narrow = geo.size.width < 150 || typeSize.isAccessibilitySize
                    if narrow {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                cardMin(compact: true)
                                cardMax(compact: true)
                            }
                            cardAvg(compact: true)
                        }
                    } else {
                        HStack(spacing: 6) {
                            cardMin(compact: false)
                            cardMax(compact: false)
                            cardAvg(compact: false)
                        }
                    }
                }
                .frame(minHeight: 0) // 高さ計算安定化
            }
        }
        .padding(.top, 2)
    }

    // カード生成ヘルパ
    private func cardMin(compact: Bool) -> some View {
        StatCard(
            title: "最低",
            systemName: "arrow.down.to.line",
            valueText: valueText(attraction.min),
            subtitle: timeText(attraction.minTime),
            tint: .cyan,
            compact: compact
        )
    }
    private func cardMax(compact: Bool) -> some View {
        StatCard(
            title: "最高",
            systemName: "arrow.up.to.line",
            valueText: valueText(attraction.max),
            subtitle: timeText(attraction.maxTime),
            tint: .orange,
            compact: compact
        )
    }
    private func cardAvg(compact: Bool) -> some View {
        StatCard(
            title: "平均",
            systemName: "gauge",
            valueText: valueText(avgDisplay),
            subtitle: avgTimeText,
            tint: .green,
            compact: compact
        )
    }

    // 表示文字列
    private func valueText(_ v: Int?) -> String { v.map { "\($0)分" } ?? "--" }
    private func timeText(_ t: String?) -> String? { (t?.isEmpty == false) ? t : nil }
    private var avgTimeText: String? {
        if let t = attraction.updatedText, !t.isEmpty { return t }
        if let d = attraction.lastUpdated { return d.formatted(date: .omitted, time: .shortened) }
        return nil
    }
}


// ミニカード部品（2行：値／時刻）
private struct StatCard: View {
    let title: String
    let systemName: String
    let valueText: String
    let subtitle: String?
    let tint: Color
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 3) {
            // 見出し（アイコン＋タイトル）← ここをより小さく
            HStack(spacing: 2) {
                Image(systemName: systemName)
                    .font(.system(size: compact ? 9 : 10)) // 旧: .caption2
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: compact ? 8 : 9)) // 旧: .caption2
                }
            }
            .foregroundStyle(.secondary)

            Text(valueText)
                .font(compact ? .caption2 : .caption)
                .bold()
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: compact ? 8 : 9))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 4 : 6)
        .background(
            RoundedRectangle(cornerRadius: compact ? 7 : 8).fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 7 : 8)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
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
        .frame(width: 44, height: 44)
    }
}

#Preview {
    ContentView()
}
