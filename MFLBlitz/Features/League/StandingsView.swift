import SwiftUI

struct StandingsView: View {
    @Environment(AppModel.self) private var model
    @State private var scope = Scope.division
    @State private var showingOrderInfo = false

    enum Scope: String, CaseIterable, Identifiable {
        case division = "Divisions"
        case overall = "Overall"
        var id: Self { self }
    }

    var body: some View {
        List {
            if model.isDemo {
                DemoBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Picker("Standings scope", selection: $scope) {
                    ForEach(Scope.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
            }

            if scope == .division {
                ForEach(divisions, id: \.self) { division in
                    Section(division) {
                        StandingsColumnHeader()
                        ForEach(rows(in: division)) { row in
                            teamLink(row)
                        }
                    }
                }
            } else {
                Section {
                    StandingsColumnHeader()
                    ForEach(model.standings.sorted(using: KeyPathComparator(\.rank))) { row in
                        teamLink(row)
                    }
                } header: {
                    Text("League")
                }
            }

        }
        .listStyle(.insetGrouped)
        .navigationTitle("Standings")
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
        .refreshable { await model.refreshAll() }
    }

    private var standingsOrderInfo: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.isDemo || model.workspace?.leagueID == "41333" {
                        Text("Record → head-to-head → points → division percentage")
                            .font(.body)
                            .accessibilityLabel("Record, then head-to-head, then points, then division percentage")
                            .accessibilityIdentifier("standings-order-rule")
                    }

                    Label(
                        "The standings are shown in the official order returned by MFL, including your league’s configured tiebreakers.",
                        systemImage: "checkmark.seal"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Official league order")
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
        .frame(idealWidth: 340, idealHeight: 300)
        .presentationCompactAdaptation(.popover)
    }

    private var divisions: [String] {
        Array(Set(model.standings.map(\.division))).sorted()
    }

    @ViewBuilder
    private func teamLink(_ row: StandingRow) -> some View {
        if let scope = model.browseScope {
            NavigationLink(value: TeamRoute(scope: scope, franchiseID: row.id)) {
                StandingTeamRow(row: row)
            }
            .accessibilityIdentifier("standings-team-\(row.id)")
            .accessibilityHint("Opens this team’s roster and schedule")
        } else {
            StandingTeamRow(row: row)
        }
    }

    private func rows(in division: String) -> [StandingRow] {
        model.standings.filter { $0.division == division }.sorted(using: KeyPathComparator(\.rank))
    }
}

private struct StandingsColumnHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Team")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("W–L")
                .frame(width: 46, alignment: .trailing)
            Text("PF")
                .frame(width: 54, alignment: .trailing)
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
    let row: StandingRow

    var body: some View {
        HStack(spacing: 10) {
            Text("\(row.rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            TeamMark(abbreviation: row.abbreviation, seed: row.accentSeed, size: 36, artworkURLs: row.artworkURLs)
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
            Text(record)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 46, alignment: .trailing)
            Text(row.pointsFor, format: .number.precision(.fractionLength(1)))
                .font(.subheadline.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
        }
        .listRowBackground(row.isUser ? Color.blitzGreen.opacity(0.08) : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(row.rank), \(row.name), \(row.ownerName.map { "Owner: \($0)" } ?? "Owner not listed"), \(row.wins) wins, \(row.losses) losses, \(row.ties) ties, \(row.pointsFor, format: .number.precision(.fractionLength(1))) points for, \(row.division) division")
        .accessibilityIdentifier("standing-\(row.id)")
    }

    private var record: String {
        row.ties > 0 ? "\(row.wins)-\(row.losses)-\(row.ties)" : "\(row.wins)-\(row.losses)"
    }
}
