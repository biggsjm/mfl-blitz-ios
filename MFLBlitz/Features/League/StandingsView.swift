import MFLCore
import SwiftUI

struct StandingsView: View {
    @Environment(AppModel.self) private var model
    @State private var scope: Scope
    @State private var showingOrderInfo = false
    @State private var didRevealFocus = false
    private let focusedFranchiseID: String?

    init(initialScope: Scope = .division, focusedFranchiseID: String? = nil) {
        _scope = State(initialValue: initialScope)
        self.focusedFranchiseID = focusedFranchiseID
    }

    enum Scope: String, CaseIterable, Identifiable {
        case division = "Divisions"
        case overall = "Overall"
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasDivisions {
                Picker("Standings scope", selection: $scope) {
                    ForEach(Scope.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("standings-scope")
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            ScrollViewReader { proxy in
                List {
                    if model.connectionMessage != nil {
                        ConnectionStatusBanner().listRowBackground(Color.clear)
                    }
                    if let saved = model.cachedStandingsDate {
                        SavedDataLabel(date: saved).listRowBackground(Color.clear)
                    }
                    if model.isDemo {
                        DemoBanner()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    if withinDivision {
                        ForEach(divisions, id: \.id) { division in
                            Section(division.name) {
                                StandingsColumnHeader(showTies: hasGameTies)
                                ForEach(rows(in: division.id)) { row in
                                    teamLink(row).id(row.id)
                                }
                            }
                        }
                    } else {
                        Section {
                            StandingsColumnHeader(showTies: hasGameTies)
                            ForEach(StandingRow.sorted(model.standings, withinDivision: false)) { row in
                                teamLink(row).id(row.id)
                            }
                        } header: {
                            Text(model.workspace?.leagueName ?? "League")
                        }
                    }
                    if let message = rankingMessage {
                        Section {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                            if let url = standingsURL { Link("View standings on MFL", destination: url) }
                        }
                    }

                }
                .listStyle(.insetGrouped)
                .navigationTitle("Standings")
                .task(id: model.standings.isEmpty) {
                    guard !didRevealFocus, !model.standings.isEmpty, let focusedFranchiseID else { return }
                    proxy.scrollTo(focusedFranchiseID, anchor: .center)
                    didRevealFocus = true
                }
                .onChange(of: scope) {
                    if let focusedFranchiseID { proxy.scrollTo(focusedFranchiseID, anchor: .center) }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingOrderInfo = true
                        } label: {
                            Label("About standings order", systemImage: "info.circle")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityIdentifier("standings-order-info")
                        .accessibilityHint("Shows how MyFantasyLeague orders tied teams")
                        .popover(
                            isPresented: $showingOrderInfo,
                            attachmentAnchor: .rect(.bounds),
                            arrowEdge: .top
                        ) {
                            standingsOrderInfo
                        }
                    }
                }
                .refreshable { await model.refreshStandings() }
            }
        }
        .pageBackground()
    }

    private var standingsOrderInfo: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let rule = model.standings.first?.standingsRule {
                        Text(
                            rule.split(separator: ",").map {
                                switch $0.trimmingCharacters(in: .whitespaces).uppercased() {
                                case "PCT": "Winning percentage"
                                case "H2H": "Head-to-head"
                                case "PTS": "Points"
                                case "DIVPCT": "Division percentage"
                                default: String($0)
                                }
                            }.joined(separator: " → ")
                        )
                        .font(.body)
                        .accessibilityIdentifier("standings-order-rule")
                    }

                    Label(
                        "Places use your league’s configured criteria. Division and overall places are calculated separately. Matching records alone don’t mean a tie. Unresolved places stay blank; MFL’s report is the final authority for custom orders.",
                        systemImage: "checkmark.seal"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Standings order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingOrderInfo = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .frame(idealWidth: 340, idealHeight: 360)
        .presentationCompactAdaptation(.popover)
    }

    private var hasDivisions: Bool { model.standings.contains { $0.hasDivision } }
    private var withinDivision: Bool { hasDivisions && scope == .division }
    private var hasGameTies: Bool { model.standings.contains { $0.ties > 0 } }
    private var divisions: [(id: String?, name: String)] {
        var seen: Set<String?> = []
        return model.standings.compactMap { row in
            let id = row.hasDivision ? row.divisionID : nil
            guard seen.insert(id).inserted else { return nil }
            return (id: id, name: row.hasDivision ? row.division : model.workspace?.leagueName ?? "League")
        }.sorted { $0.name == $1.name ? ($0.id ?? "") < ($1.id ?? "") : $0.name < $1.name }
    }
    private var rankingMessage: String? {
        let issues = model.standings.compactMap {
            withinDivision && $0.hasDivision ? $0.divisionRankIssue : $0.overallRankIssue
        }
        guard !issues.isEmpty else { return nil }
        if issues.allSatisfy({ $0 == .awaitingResults }) { return "Places appear after the first results." }
        return "Some places couldn’t be determined. Check MFL for the complete standings."
    }
    private var standingsURL: URL? {
        guard let workspace = model.workspace else { return nil }
        return URL(string: "\(workspace.baseURL.absoluteString)/\(workspace.season)/standings?L=\(workspace.leagueID)")
    }

    @ViewBuilder
    private func teamLink(_ row: StandingRow) -> some View {
        if let scope = model.browseScope {
            NavigationLink(value: TeamRoute(scope: scope, franchiseID: row.id)) {
                StandingTeamRow(row: row, withinDivision: withinDivision, showTies: hasGameTies)
            }
            .accessibilityIdentifier("standings-team-\(row.id)")
            .accessibilityHint("Opens this team’s roster and schedule")
        } else {
            StandingTeamRow(row: row, withinDivision: withinDivision, showTies: hasGameTies)
        }
    }

    private func rows(in division: String?) -> [StandingRow] {
        StandingRow.sorted(
            model.standings.filter { ($0.hasDivision ? $0.divisionID : nil) == division }, withinDivision: true)
    }
}

private struct StandingsColumnHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let showTies: Bool
    var body: some View {
        HStack(spacing: 10) {
            Text("Team")
                .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(showTies ? "W–L–T" : "W–L")
                    .frame(width: showTies ? 62 : 46, alignment: .trailing)
                Text("PF")
                    .frame(width: 54, alignment: .trailing)
            }
        }
        // Match the native disclosure space on the tappable rows below.
        .padding(.trailing, 22)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .accessibilityHidden(true)
    }
}

private struct StandingTeamRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let row: StandingRow
    let withinDivision: Bool
    let showTies: Bool
    private var place: MFLStandingPlace? { withinDivision && row.hasDivision ? row.divisionPlace : row.overallPlace }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(place.map { ($0.isTied ? "T" : "") + String($0.position) } ?? "—")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .fixedSize()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).font(.headline)
                            Text(row.ownerName ?? "Owner not listed")
                                .font(.caption).foregroundStyle(.secondary)
                            if row.isUser { Text("Your team").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Text(row.recordText ?? "Record unavailable").font(.subheadline)
                    Text("\(row.pointsFor, format: .number.precision(.fractionLength(1))) points for")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    Text(place.map { ($0.isTied ? "T" : "") + String($0.position) } ?? "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    TeamMark(
                        abbreviation: row.abbreviation, seed: row.accentSeed, size: 36, artworkURLs: row.artworkURLs)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(row.name)
                                .font(.subheadline.weight(row.isUser ? .bold : .medium))
                                .lineLimit(2)
                            if row.isUser {
                                Text("YOU")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(Color.blitzNavy)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.blitzGreen, in: Capsule())
                            }
                        }
                        Text(row.ownerName ?? "Owner not listed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.recordText ?? "—")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(width: showTies ? 62 : 46, alignment: .trailing)
                    Text(row.pointsFor, format: .number.precision(.fractionLength(1)))
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
        .listRowBackground(row.isUser ? Color.blitzGreen.opacity(0.08) : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(place.map { "\($0.isTied ? "Tied at " : "")\(withinDivision && row.hasDivision ? "Division" : "League") rank \($0.position)" } ?? "Place unavailable"), \(row.name), \(row.ownerName.map { "Owner: \($0)" } ?? "Owner not listed"), \(row.recordText ?? "Record unavailable"), \(row.pointsFor, format: .number.precision(.fractionLength(1))) points for"
        )
        .accessibilityIdentifier("standing-\(row.id)")
    }

}
