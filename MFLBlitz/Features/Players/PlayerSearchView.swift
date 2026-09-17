import SwiftUI

private enum PlayerSearchFocus: Hashable { case button, field }
/// A focused field and bounded results keep the originating screen mounted.
/// Player details use that screen's existing navigation path.
private struct PlayerSearchModifier<Actions: View>: ViewModifier {
    let actions: Actions
    @Environment(AppModel.self) private var model
    @Environment(\.openPlayerRoute) private var openPlayerRoute
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    @State private var isVisible = false
    @State private var focusRequested = false
    @State private var contentHeight: CGFloat = 72
    @FocusState private var isFocused: Bool
    @AccessibilityFocusState private var accessibilityFocus: PlayerSearchFocus?

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(isPresented)
            .allowsHitTesting(!isPresented)
            .overlay(alignment: .top) {
                if isPresented {
                    GeometryReader { geometry in
                        ZStack(alignment: .top) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(perform: close)
                                .accessibilityHidden(true)

                            PlayerSearchContent(contentHeight: $contentHeight, dismissKeyboard: dismissKeyboard) { player in
                                guard let scope = model.browseScope else { return }
                                dismissKeyboard()
                                model.playerSearch.remember(player)
                                openPlayerRoute?(PlayerRoute(scope: scope, playerID: player.id,
                                    inspectedWeek: model.currentWeek, previewIdentity: player))
                            }
                            .frame(height: panelHeight(available: geometry.size.height))
                            .clipShape(RoundedRectangle(cornerRadius: BlitzMetrics.cornerRadius))
                            .overlay { RoundedRectangle(cornerRadius: BlitzMetrics.cornerRadius).stroke(.primary.opacity(0.08)) }
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                            .padding(.horizontal, BlitzMetrics.pagePadding)
                            .padding(.top, 6)
                            .readablePageWidth()
                            .accessibilityIdentifier("player-search-results")
                        }
                    }
                    .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if isPresented { field.transition(.opacity) }
            }
            .navigationBarTitleDisplayMode(isPresented ? .inline : .automatic)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Keep screen actions and search in one ordered group. Separate
                    // toolbar modifiers can reverse their order across screens.
                    actions
                    Button(isPresented ? "Close search" : "Search players", systemImage: isPresented ? "xmark" : "magnifyingglass") {
                        if isPresented { close() }
                        else {
                            focusRequested = true
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { isPresented = true }
                        }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier(isPresented ? "close-player-search" : "global-player-search")
                    .accessibilityHint(isPresented ? "Closes search and returns to this page" : "Find any player and see who owns them")
                    .accessibilityFocused($accessibilityFocus, equals: .button)
                }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false; isFocused = false; accessibilityFocus = nil }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { isFocused = false; accessibilityFocus = nil }
            }
            .onChange(of: model.browseScope) { close() }
            .task(id: "\(isPresented)|\(isVisible)") {
                guard isPresented, isVisible, focusRequested, scenePhase == .active else { return }
                await Task.yield()
                guard !Task.isCancelled, isPresented, isVisible else { return }
                focusRequested = false; isFocused = true; accessibilityFocus = .field
            }
    }

    private var field: some View {
        @Bindable var search = model.playerSearch
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search players", text: $search.query)
                .accessibilityLabel("Search players")
                .focused($isFocused)
                .accessibilityFocused($accessibilityFocus, equals: .field)
                .accessibilityIdentifier("player-search-field")
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit(dismissKeyboard)
            if !search.query.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { search.query = ""; isFocused = true }
                    .labelStyle(.iconOnly).foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("clear-player-search")
            }
        }
        .padding(.leading, 12).padding(.trailing, search.query.isEmpty ? 12 : 0)
        .frame(minHeight: 44)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: BlitzMetrics.compactCornerRadius))
        .padding(.horizontal, BlitzMetrics.pagePadding).padding(.vertical, 8)
        .readablePageWidth()
        .background(.bar)
    }

    private func panelHeight(available: CGFloat) -> CGFloat {
        let desired = max(72, contentHeight)
        return max(0, min(desired, min(dynamicTypeSize.isAccessibilitySize ? 760 : 520, available * (dynamicTypeSize.isAccessibilitySize ? 0.98 : 0.82))))
    }

    private func dismissKeyboard() {
        isFocused = false; focusRequested = false
        accessibilityFocus = nil
    }

    private func close() {
        dismissKeyboard()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { isPresented = false }
        model.playerSearch.query = ""
        if isVisible { accessibilityFocus = .button }
    }
}

extension View {
    func playerSearch() -> some View { playerSearch { EmptyView() } }

    func playerSearch<Actions: View>(@ViewBuilder actions: () -> Actions) -> some View {
        modifier(PlayerSearchModifier(actions: actions()))
    }
}

private struct PlayerSearchContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Binding var contentHeight: CGFloat
    let dismissKeyboard: () -> Void
    let openPlayer: (PlayerIdentity) -> Void

    private var search: PlayerSearchModel { model.playerSearch }
    private var trimmedQuery: String { search.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if model.isUsingCachedSession {
                Section {
                    Label("Reconnect your league to search all players.", systemImage: "wifi.exclamationmark")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                statusSection
                if trimmedQuery.isEmpty {
                    if search.recentPlayers.isEmpty {
                        Text("Search by name, team or position.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Section {
                            ForEach(search.recentPlayers) { player in resultRow(player); Divider() }
                        } header: {
                            HStack {
                                Text("Recent players")
                                Spacer()
                                Button("Clear") { search.clearRecents() }
                                    .accessibilityLabel("Clear recent players")
                            }.textCase(nil)
                        }
                    }
                } else if !search.results.players.isEmpty {
                    Section {
                        ForEach(search.results.players) { player in resultRow(player); Divider() }
                    } header: {
                        Text("\(search.results.total) \(search.results.total == 1 ? "player" : "players")").font(.caption)
                    } footer: {
                        if search.results.total > search.results.players.count {
                            Text("Showing the first \(search.results.players.count). Add a name or NFL team to narrow your search.")
                        }
                    }
                } else if search.hasCatalog && !search.isLoadingCatalog {
                    Text("No players found. Try another name, NFL team, or position.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
          }
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
              if height.isFinite && height > 0 { contentHeight = height }
          }
        }
        .background(.background)
        .playerJerseyMetadata(for: search.query.isEmpty ? search.recentPlayers.map(\.id) : search.results.players.map(\.id))
        .scrollDismissesKeyboard(.immediately)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { dismissKeyboard() }
        }
        .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
        .task(id: readKey) {
            guard scenePhase == .active else { return }
            await loadCatalog()
        }
        .task(id: readKey) { if scenePhase == .active { await loadOwnership() } }
        .task(id: "\(readKey)|\(model.currentWeek)") {
            if scenePhase == .active { await model.loadPlayerAvailability(week: model.currentWeek) }
        }
        .task(id: "\(search.catalogVersion)|\(search.query)") {
            await search.search(franchiseID: model.workspace?.franchiseID,
                fantasyValues: PlayerSearchRankingContext.cachedFantasyValues(week: model.currentWeek,
                    scores: model.scores, lineup: model.lineup, waivers: model.waivers))
        }
        .refreshable { await load(force: true) }
    }

    @ViewBuilder private var statusSection: some View {
        if search.isLoadingCatalog && !search.hasCatalog {
            Section { ProgressView("Loading players…").frame(maxWidth: .infinity) }
        }
        if let error = search.catalogError {
            Section {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                Button("Retry player list") { Task { await load() } }
            }
        }
        if let error = search.ownershipError {
            Section {
                HStack {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { Task { await load(force: true) } }
                        .disabled(search.isLoadingOwnership)
                        .accessibilityLabel("Retry player ownership")
                }
            }
        } else if search.isLoadingOwnership {
            Section {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Updating ownership…").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func resultRow(_ player: PlayerIdentity) -> some View {
        Button {
            openPlayer(player)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    PlayerNameCaption(name: player.name, playerID: player.id, nflTeam: player.nflTeam,
                        jerseyNumber: player.jerseyNumber, position: player.position)
                    PlayerAvailabilityCaption(playerID: player.id, nflTeam: player.nflTeam ?? "", week: model.currentWeek)
                    Text(ownershipText(player.id)).font(.subheadline).foregroundStyle(.primary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("search-player-\(player.id)")
        .accessibilityHint("Opens player details")
    }

    private func ownershipText(_ playerID: String) -> String {
        guard let ownership = search.ownership else {
            return search.isLoadingOwnership ? "Checking ownership…" : "Ownership unavailable"
        }
        let summary = ownership.summary(for: playerID,
            scores: model.cachedScoresDate == nil ? model.scores : nil, currentWeek: model.currentWeek)
        let label = (ownership.assignments[playerID]?.isEmpty == false ? "Rostered by " : "") + summary
        return search.ownershipError == nil ? label : "Last known: \(label)"
    }

    private var readKey: String {
        "\(model.workspace?.storageScope ?? "none")|\(model.isUsingCachedSession)|\(model.rosterRevision)|\(scenePhase)"
    }

    private func load(force: Bool = false) async {
        await loadCatalog()
        await loadOwnership(force: force)
    }

    private func loadCatalog() async {
        guard !model.isUsingCachedSession, let scope = model.workspace?.storageScope else { return }
        await search.loadCatalog(scope: scope) { try await model.loadPlayerSearchCatalog() }
    }

    private func loadOwnership(force: Bool = false) async {
        guard !model.isUsingCachedSession, let scope = model.workspace?.storageScope else { return }
        // Separate view tasks let names appear without waiting for membership.
        await search.loadOwnership(scope: scope, revision: model.rosterRevision, force: force) {
            try await model.loadPlayerSearchOwnership(refresh: $0)
        }
    }
}
