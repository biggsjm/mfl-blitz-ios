import SwiftUI

struct StandingsView: View {
    @Environment(AppModel.self) private var model
    @State private var scope = Scope.division

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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Official league order")
                        .font(.headline)
                    Text("Record → head-to-head → points → division percentage")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Standings scope", selection: $scope) {
                        ForEach(Scope.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }

            if scope == .division {
                ForEach(divisions, id: \.self) { division in
                    Section(division) {
                        StandingsColumnHeader()
                        ForEach(rows(in: division)) { row in
                            StandingTeamRow(row: row)
                        }
                    }
                }
            } else {
                Section {
                    StandingsColumnHeader()
                    ForEach(model.standings.sorted(using: KeyPathComparator(\.rank))) { row in
                        StandingTeamRow(row: row)
                    }
                } header: {
                    Text("League")
                }
            }

            Section {
                Label("Standing order comes from MFL, including your league’s custom tiebreakers.", systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Standings")
        .refreshable { await model.refreshAll() }
    }

    private var divisions: [String] {
        Array(Set(model.standings.map(\.division))).sorted()
    }

    private func rows(in division: String) -> [StandingRow] {
        model.standings.filter { $0.division == division }.sorted(using: KeyPathComparator(\.rank))
    }
}

private struct StandingsColumnHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Team")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("W–L")
                .frame(width: 46, alignment: .trailing)
            Text("PF")
                .frame(width: 54, alignment: .trailing)
        }
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
            TeamMark(abbreviation: row.abbreviation, seed: row.accentSeed, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(row.name)
                        .font(.subheadline.weight(row.isUser ? .bold : .medium))
                        .lineLimit(1)
                    if row.isUser {
                        Text("YOU")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Color.blitzNavy)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blitzGreen, in: Capsule())
                    }
                }
                Text(row.streak == "—" ? row.division : "\(row.division) · \(row.streak)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .accessibilityLabel("Rank \(row.rank), \(row.name), \(row.wins) wins, \(row.losses) losses, \(row.ties) ties, \(row.pointsFor, format: .number.precision(.fractionLength(1))) points for, \(row.division) division")
    }

    private var record: String {
        row.ties > 0 ? "\(row.wins)-\(row.losses)-\(row.ties)" : "\(row.wins)-\(row.losses)"
    }
}
