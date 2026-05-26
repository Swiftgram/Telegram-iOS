import SwiftUI

private struct ScrollSnapshot: Equatable {
    let contentOffsetY: CGFloat
    let contentSizeH: CGFloat
    let containerSizeH: CGFloat
    let topInset: CGFloat
}

struct MessageListView: View {
    @Environment(TDClient.self) private var client
    let row: ChatRow

    @State private var store: ChatHistoryStore?
    @State private var presentedPhoto: PhotoVisual?
    @State private var presentedVideo: VideoVisual?
    @State private var presentedVideoNote: VideoNoteVisual?
    @State private var presentedPoll: PollVoteTarget?
    @State private var showCompose: Bool = false
    @State private var showAttachment: Bool = false
    @State private var stickerPickerStore: StickerPickerStore?
    // True when the user is parked within slop of the bottom edge. Updated only on
    // user-driven scrolls (see .onScrollGeometryChange filter), so it reflects intent
    // rather than instantaneous viewport position. Drives auto-scroll for incoming:
    // stay-anchored-when-at-bottom, leave-alone-when-scrolled-up. Initial value depends
    // on whether the chat opens at the tail (no unreads → true) or at the unread divider
    // (unreads present → false, user is parked at the divider, not the bottom).
    @State private var isAtBottom: Bool
    @State private var didApplyInitialScroll: Bool = false
    // Pagination triggers fire from `.onScrollVisibilityChange` on the top/bottom rows.
    // On initial layout — especially for all-unread chats where the divider lands at
    // row index 0 — the topmost rows are visible without any user gesture, which would
    // call loadOlder() repeatedly in a loop as each fetch prepends more content. Gate
    // pagination on having observed at least one user-driven scroll
    // (`.onScrollGeometryChange`'s contentSizeH-stable filter implies user-driven).
    @State private var userHasScrolled: Bool = false
    // Hard cool-down after each loadOlder/loadNewer. Without this, the row-visibility
    // callbacks for newly-prepended rows fire IMMEDIATELY after `reproject()` and re-
    // trigger pagination before SwiftUI can land the `.onChange`-driven scroll-preservation
    // animation. The cool-down lets the prepended rows settle off-screen before the
    // next pagination is allowed.
    @State private var canPaginate: Bool = true

    init(row: ChatRow) {
        self.row = row
        // Opens at tail → starts at bottom. Opens at divider → user is NOT at bottom.
        self._isAtBottom = State(initialValue: row.unreadCount == 0)
    }

    var body: some View {
        Group {
            if let store {
                content(store: store)
            } else {
                LoadingView(label: "Loading…")
            }
        }
        .navigationTitle(row.title)
        .accessibilityIdentifier("messageListView")
        .sheet(item: $presentedPhoto) { photo in
            PhotoViewerView(photo: photo)
        }
        .sheet(item: $presentedVideo) { video in
            if let store {
                VideoPlayerView(video: video).environment(store)
            }
        }
        .sheet(item: $presentedVideoNote) { note in
            if let store {
                VideoNotePlayerView(note: note).environment(store)
            }
        }
        .sheet(item: $presentedPoll) { target in
            if let store {
                PollVoteView(
                    initialPoll: target.poll,
                    currentPoll: { store.poll(forMessageId: target.id) },
                    onVote: { await store.setPollAnswer(messageId: target.id, optionIds: $0) }
                )
            }
        }
        .sheet(isPresented: $showCompose) {
            if let store {
                ComposeSheet(
                    initialText: store.draftText,
                    onSend: { text in
                        await store.sendText(text)
                        return store.lastSendError == nil
                    },
                    onDismissWithDraft: { text in await store.saveDraft(text) }
                )
            }
        }
        .sheet(isPresented: $showAttachment) {
            if let store {
                AttachmentSheet(
                    stickerPickerStore: stickerPickerStore,
                    onSendSticker: { await store.sendSticker($0) },
                    onSendVoiceNote: { await store.sendVoiceNote($0) },
                    onPrepareVoice: {
                        store.voicePlayback.tearDown()
                        store.audioPlayback.tearDown()
                    },
                    onSendLocation: { latitude, longitude in
                        await store.sendLocation(latitude: latitude, longitude: longitude)
                    }
                )
                .environment(client)
            }
        }
        .task {
            guard store == nil, let loader = client.makeChatHistoryLoader() else { return }
            let s = ChatHistoryStore(
                chatId: row.id,
                chatType: row.chatType,
                lastReadInboxMessageId: row.lastReadInboxMessageId,
                lastReadOutboxMessageId: row.lastReadOutboxMessageId,
                unreadCount: row.unreadCount,
                lastMessageId: row.lastMessageId,
                loader: loader,
                selfUserId: client.me?.id,
                userNames: client.userNames,
                draftText: row.draftText,
                coalesceUpdates: true
            )
            self.store = s
            client.setActiveHistory(s)
            // Build the picker store HERE (in the chat .task), not lazily in the
            // attachment-tap closure. Creating an @State and flipping a sheet-present
            // flag in the same closure races: the .sheet evaluates `if let pickerStore`
            // against a snapshot where the store is still nil → empty body. Having it
            // non-nil before the tap (like `store` above) avoids that.
            if stickerPickerStore == nil, let pl = client.makeStickerPickerLoader() {
                stickerPickerStore = StickerPickerStore(loader: pl)
            }
            await s.start()
        }
        .onDisappear {
            let s = self.store
            client.setActiveHistory(nil)
            Task { await s?.stop() }
        }
    }

    @ViewBuilder
    private func content(store: ChatHistoryStore) -> some View {
        switch store.loadState {
        case .loadingFirstPage:
            // Keep the spinner up for the entire initial load. TDLib's cold cache
            // routinely splits `getChatHistory` into multiple round-trips (iter=1
            // returns 1 message, iter=2 returns the rest). If we fall through to
            // the ScrollView mid-load, the user sees: brief render with iter=1's
            // content → iter=2 prepends 29 messages (content jumps) → final scroll
            // fires. Showing the spinner until `.loaded` collapses that into one
            // clean transition.
            LoadingView(label: "Loading messages…")
        case .failed(let message):
            VStack(spacing: 6) {
                Text(message)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await store.start() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        default:
            // ScrollViewReader is hoisted ABOVE the VStack so the
            // `.overlay(alignment: .bottomTrailing) { ... }` jump-to-bottom button
            // can capture `proxy` and call `proxy.scrollTo(...)` after jumpToBottom.
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if let err = store.lastSendError {
                        HStack(spacing: 4) {
                            Text(err)
                                .font(.caption2)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Button {
                                store.dismissSendError()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(6)
                        .background(Capsule().fill(.red.opacity(0.2)))
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                    }
                    if let err = store.lastPaginationError {
                        HStack(spacing: 4) {
                            Text(err).font(.caption2).lineLimit(2)
                            Spacer(minLength: 0)
                            Button { store.dismissPaginationError() } label: {
                                Image(systemName: "xmark").font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(6)
                        .background(Capsule().fill(.orange.opacity(0.2)))
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(store.rows.enumerated()), id: \.element.id) { idx, messageRow in
                                MessageRowView(
                                    row: messageRow,
                                    onPhotoTap: { presentedPhoto = $0 },
                                    onVideoTap: { presentedVideo = $0 },
                                    onVideoNoteTap: { presentedVideoNote = $0 },
                                    onPollTap: { id, poll in presentedPoll = PollVoteTarget(id: id, poll: poll) },
                                    index: idx,
                                    count: store.rows.count,
                                    onEnterTopEdge: {
                                        guard userHasScrolled, canPaginate else { return }
                                        canPaginate = false
                                        Task {
                                            await store.loadOlder()
                                            try? await Task.sleep(nanoseconds: 800_000_000)
                                            canPaginate = true
                                        }
                                    },
                                    onEnterBottomEdge: {
                                        guard userHasScrolled, canPaginate, !store.window.reachesChatTail else { return }
                                        canPaginate = false
                                        Task {
                                            await store.loadNewer()
                                            try? await Task.sleep(nanoseconds: 800_000_000)
                                            canPaginate = true
                                        }
                                    },
                                    onIncomingBubbleVisible: { id in
                                        guard id > store.unreadDividerAfterIdSnapshot else { return }
                                        store.markVisible(messageId: id)
                                    }
                                )
                                .id(messageRow.id)
                            }
                            if row.canSend {
                                ReplyBar(
                                    onAttachTap: { showAttachment = true },
                                    onTextTap: { showCompose = true }
                                )
                                .id("composeAnchor")
                                .padding(.top, 8)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                    }
                    .defaultScrollAnchor(.bottom)
                    .environment(store)
                    .task {
                        // Default branch only appears once `loadState == .loaded`
                        // (the .loadingFirstPage case above keeps the spinner up).
                        // .task fires once per view appearance; the guard makes the
                        // scroll idempotent across re-renders. A short sleep lets
                        // SwiftUI lay out the freshly-rendered VStack before scrollTo
                        // resolves the target id — otherwise scrollTo can land before
                        // the row exists in the rendered tree.
                        //
                        // .defaultScrollAnchor(.bottom) on the ScrollView above
                        // positions the no-divider case at the chat tail BEFORE this
                        // task fires (so the user never sees the top-flash). We only
                        // need to override that for the unread-divider case.
                        guard !didApplyInitialScroll else { return }
                        didApplyInitialScroll = true
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        if let target = store.window.initialScrollTargetId {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                    .onScrollGeometryChange(for: ScrollSnapshot.self) { geometry in
                        ScrollSnapshot(
                            contentOffsetY: geometry.contentOffset.y,
                            contentSizeH: geometry.contentSize.height,
                            containerSizeH: geometry.containerSize.height,
                            topInset: geometry.contentInsets.top
                        )
                    } action: { old, new in
                        // isAtBottom means "user intends to be parked at bottom", NOT "the
                        // bottom edge is visible right now". When a new message arrives while
                        // the user is at the bottom, contentSize grows but contentOffset stays
                        // — a naive "is the bottom edge visible" check would flip false even
                        // though the user hasn't moved. Skipping callbacks where contentSize
                        // changed preserves the last user-driven state.
                        //
                        // The .top inset (translucent nav bar overlay, ~62pt on the 46mm sim)
                        // shrinks the maximum scroll offset; subtract it from bottomOffset or
                        // the check is off by ~62pt and isAtBottom never reaches true. Verified
                        // empirically — when at the bottom, contentOffset.y ==
                        // contentSize.height - containerSize.height - contentInsets.top.
                        guard old.contentSizeH == new.contentSizeH else { return }
                        let bottomOffset = new.contentSizeH - new.containerSizeH - new.topInset
                        isAtBottom = new.contentOffsetY >= bottomOffset - 8
                        // contentSize-stable changes imply user-driven scroll; arm
                        // pagination so it only fires after the user actually moved.
                        userHasScrolled = true
                    }
                    .onChange(of: store.rows.first?.id) { oldId, newId in
                        // Scroll preservation across `loadOlder`. When older content is
                        // prepended, SwiftUI keeps the absolute scroll offset where it was
                        // — meaning the user was at pixel 0 (top of old content) and is
                        // now at pixel 0 of the new (longer) content, which exposes the
                        // newly-prepended top rows. Those rows' `index <= 2` triggers a
                        // fresh `loadOlder` and the chat enters a paginate-forever loop.
                        // Snap the user back to the previously-first row so the prepended
                        // content lands above the viewport (off-screen until the user
                        // chooses to scroll there).
                        guard didApplyInitialScroll,
                              let oldId, let newId, oldId != newId else { return }
                        proxy.scrollTo(oldId, anchor: .top)
                    }
                    .onChange(of: store.rows.last?.id) { _, newId in
                        // Telegram convention: outgoing always pulls to bottom; incoming only
                        // pulls if the user was already parked there. Only auto-scroll when we
                        // actually have the chat tail loaded — otherwise rows.last is just the
                        // bottom of the current window, not the latest message. Also gate on
                        // didApplyInitialScroll so the initial fill (where rows.last?.id
                        // transitions from nil → some-id mid-load) doesn't double-fire with
                        // the .task initial-scroll handler.
                        guard didApplyInitialScroll,
                              newId != nil,
                              store.window.reachesChatTail,
                              case .bubble(let bubble) = store.rows.last else { return }
                        guard bubble.isOutgoing || isAtBottom else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            if row.canSend {
                                proxy.scrollTo("composeAnchor", anchor: .bottom)
                            } else if let lastId = store.rows.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // Hidden when at the bottom; visible when there's something newer
                    // (unseen incomings OR a non-tail-reaching window).
                    if !isAtBottom && (store.unseenNewerCount > 0 || !store.window.reachesChatTail) {
                        Button {
                            Task {
                                await store.jumpToBottom()
                                // jumpToBottom's slow path rebuilds the window in place without
                                // cycling loadState, so the .onChange(of: loadState) handler doesn't
                                // re-fire. We scroll directly here, which handles both paths:
                                //  - Fast path (already at tail): rows unchanged, scroll to current last.
                                //  - Slow path (window rebuilt): rows.last is the new chat tail after
                                //    the await returns.
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if row.canSend {
                                        proxy.scrollTo("composeAnchor", anchor: .bottom)
                                    } else if let lastId = store.rows.last?.id {
                                        proxy.scrollTo(lastId, anchor: .bottom)
                                    }
                                }
                            }
                        } label: {
                            JumpButtonGlyph(badgeCount: store.unseenNewerCount)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 6)
                        .padding(.bottom, 6)
                        .accessibilityIdentifier("jumpToBottom")
                    }
                }
            }
        }
    }
}

/// Visual glyph for the jump-to-bottom button. The real button at the
/// MessageListView overlay wraps this in a Button, and the #Preview blocks
/// below render it directly so layout changes are visible in snapshots.
private struct JumpButtonGlyph: View {
    let badgeCount: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white, .blue)
            if badgeCount > 0 {
                Text("\(min(badgeCount, 99))")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.red))
                    .foregroundStyle(.white)
                    .offset(x: 6, y: -4)
            }
        }
    }
}

#if DEBUG
#Preview("Jump no badge") { JumpButtonGlyph(badgeCount: 0).padding() }
#Preview("Jump badge 1") { JumpButtonGlyph(badgeCount: 1).padding() }
#Preview("Jump badge 12") { JumpButtonGlyph(badgeCount: 12).padding() }
#Preview("Jump badge 99+") { JumpButtonGlyph(badgeCount: 250).padding() }
#endif
