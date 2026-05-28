import SwiftUI
import TDLibKit

struct ChatListView: View {
    @Environment(TDClient.self) private var client
    let store: ChatListStore

    @State private var dismissedLastError: String? = nil
    /// Bound to the outer chat-list `List`. Re-asserted after every pill tap so the
    /// digital crown stays glued to the chat list, never the pill bar's horizontal
    /// ScrollView (where rotation has no useful effect). watchOS otherwise routes
    /// the crown to the most-recently-interacted scrollable.
    @FocusState private var listFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if case .failed(let message) = store.loadState(for: store.currentFolder) {
                        banner(text: message, kind: .retry)
                    }
                    if let err = client.lastError, dismissedLastError != err {
                        banner(text: err, kind: .dismiss)
                    }
                    content(proxy: proxy)
                }
                // Gradient is .overlay on the chat-list VStack — NOT a sibling
                // of NavigationStack. Earlier this lived in an outer ZStack and
                // rendered on top of every pushed destination (e.g. MessageListView's
                // back chevron + title), since ZStack draws siblings front-to-back
                // regardless of which destination is current. Scoping it to the
                // root view's overlay restricts it to the chat list itself.
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [.black.opacity(0.8), .black.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 48)
                    .allowsHitTesting(false)
                    .ignoresSafeArea(edges: .top)
                }
                .navigationDestination(for: ChatRow.self) { row in
                    MessageListView(row: row)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                // Must live INSIDE the NavigationStack so the modifier's
                // .navigationDestination(isPresented:) attaches to it.
                .accountSwitcherSheet(presentation: .push, logoutAffordance: .allowed)
            }
        }
        .accessibilityIdentifier("chatListView")
    }

    @ViewBuilder
    private func content(proxy: ScrollViewProxy) -> some View {
        // One List for all states. Keeping the surrounding container stable across
        // loading/empty/populated transitions means the FolderPillBar row keeps its
        // SwiftUI identity — and its inner horizontal ScrollView keeps its offset —
        // across folder switches.
        let folderLoadState = store.loadState(for: store.currentFolder)
        List {
            if store.pills.count > 1 {
                FolderPillBar(pills: store.pills, onSelect: { pill in
                    switchTo(pill: pill, proxy: proxy)
                }, onUserInteraction: {
                    listFocused = true
                })
                .id("folderPillBarRow")
                // Negative bottom inset compresses the natural ~23pt gap between
                // the pill row and the first chat row down to ~8pt.
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: -15, trailing: 0))
                .listRowBackground(Color.clear)
                // Belt-and-suspenders: also catch tap-only cases (no scroll offset change)
                // via a simultaneous drag gesture. The onUserInteraction callback on
                // FolderPillBar handles the horizontal-pan case via onScrollGeometryChange.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0).onEnded { _ in
                        listFocused = true
                    }
                )
            }
            if store.chats.isEmpty {
                emptyStateRow(loadState: folderLoadState)
            } else {
                ForEach(Array(store.chats.enumerated()), id: \.element.id) { idx, row in
                    NavigationLink(value: row) {
                        ChatRowView(
                            row: row,
                            onRequestDownload: { store.requestFileDownload(fileId: $0) },
                            onCancelDownload: { store.cancelFileDownload(fileId: $0) }
                        )
                    }
                    .onAppear { store.ensureChatsLoaded(near: idx) }
                }
            }
        }
        .listStyle(.plain)
        .focused($listFocused)
        .onAppear { listFocused = true }
        // Hide the empty title bar so the chat list starts directly under the
        // system clock. Pill bar is the first List row, so it scrolls with content.
        .toolbar(.hidden, for: .navigationBar)
        // `.toolbar(.hidden)` hides the bar visuals but watchOS still reserves
        // ~30pt of layout. With a pill bar present, pull up by 38 (slot + 8)
        // so the pill row sits ~8pt under the clock — the gradient masks any
        // overlap, and the negative bottom inset on the pill row tightens the
        // gap to the first chat row to ~8pt. Without a pill bar the first row
        // IS a chat row, so we stop at -22 (slot - 8) to leave ~8pt of clear
        // space below the clock instead of shoving the chat row into the time
        // readout.
        .padding(.top, store.pills.count > 1 ? -38 : -22)
    }

    @ViewBuilder
    private func emptyStateRow(loadState: LoadState) -> some View {
        Group {
            if loadState == .loadingFirstPage {
                LoadingView(label: "Loading chats…")
            } else {
                Text(store.folders.isEmpty ? "No chats yet" : "No chats in this folder")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .listRowBackground(Color.clear)
    }

    private func switchTo(pill: FolderPill, proxy: ScrollViewProxy) {
        store.setCurrentFolder(pill.chatList)
        // Reset outer vertical scroll to the top. The pill bar row keeps its SwiftUI
        // identity (single List across all states + stable `.id("folderPillBarRow")`),
        // so the inner horizontal ScrollView's offset survives the folder switch.
        withAnimation {
            proxy.scrollTo("folderPillBarRow", anchor: .top)
        }
        // Re-claim crown focus for the outer List — otherwise the pill tap leaves
        // crown focus on the horizontal pill ScrollView.
        listFocused = true
    }

    private enum BannerKind { case retry, dismiss }

    @ViewBuilder
    private func banner(text: String, kind: BannerKind) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.caption2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch kind {
            case .retry:
                Button("Retry") { store.retry() }
                    .font(.caption2)
                    .buttonStyle(.borderedProminent)
            case .dismiss:
                Button {
                    dismissedLastError = client.lastError
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial)
    }
}
