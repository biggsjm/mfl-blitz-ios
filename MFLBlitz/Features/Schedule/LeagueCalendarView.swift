import SwiftUI
import MFLCore
import EventKit
import EventKitUI

struct LeagueCalendarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let calendar: LeagueCalendarModel
    var showsControls = true
    @State private var earlier = false
    @State private var showingSettings = false

    private var groups: [(String, [MFLCalendarOccurrence])] {
        let now = Date()
        let system = Calendar.current
        let weekEnd = system.dateInterval(of: .weekOfYear, for: now)?.end ?? now
        let future = calendar.feed.snapshot?.events.filter { $0.start >= now } ?? []
        let today = future.filter { system.isDateInToday($0.start) }
        let thisWeek = future.filter { !system.isDateInToday($0.start) && $0.start < weekEnd }
        let later = future.filter { !system.isDateInToday($0.start) && $0.start >= weekEnd }
        return [("Today", today), ("This week", thisWeek), ("Later", later)].filter { !$0.1.isEmpty }
    }

    var body: some View {
        List {
            if app.isDemo {
                Label("Preview · No live changes", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if let snapshot = calendar.feed.snapshot {
                if let error = calendar.feed.errorMessage { Label(error, systemImage: "wifi.exclamationmark").font(.subheadline) }
                if !snapshot.source.recurrenceVerified {
                    Label("Some repeating dates couldn’t be verified. Only confirmed dates are shown.", systemImage: "calendar.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if groups.isEmpty {
                    ContentUnavailableView("No upcoming events", systemImage: "calendar",
                        description: Text("Pull to check for new league dates."))
                        .listRowBackground(Color.clear)
                }
                ForEach(groups, id: \.0) { title, events in
                    Section(title) { ForEach(events) { event in row(event) } }
                }
                let past = snapshot.events.filter { $0.start < Date() }.reversed()
                if !past.isEmpty {
                    Section {
                        DisclosureGroup("Earlier events", isExpanded: $earlier) {
                            ForEach(Array(past)) { event in row(event) }
                        }
                    }
                }
                Section {
                    Text(ScheduleFreshness.label(updatedAt: snapshot.fetchedAt, now: Date()))
                        .font(.caption).foregroundStyle(.secondary)
                }.listRowBackground(Color.clear)
            } else if calendar.feed.isLoading {
                ProgressView("Loading league calendar…").frame(maxWidth: .infinity).padding()
            } else {
                ContentUnavailableView {
                    Label("Calendar unavailable", systemImage: "calendar.badge.exclamationmark")
                } description: { Text(calendar.feed.errorMessage ?? "Pull to load league dates.") } actions: {
                    Button("Try again") { Task { await calendar.refresh(force: true) } }
                }
            }
        }
        .accessibilityIdentifier("league-calendar")
        .navigationDestination(for: CalendarEventRoute.self) { route in
            LeagueCalendarEventView(calendar: calendar, eventID: route.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if showsControls {
                Button("Reminders", systemImage: "bell") { showingSettings = true }
                    .accessibilityIdentifier("calendar-reminder-settings")
                }
            }
        }
        .task { guard !app.isUsingCachedSession else { return }; await calendar.refresh() }
        .refreshable { await calendar.refresh(force: true) }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { DeadlineReminderSettings(calendar: calendar) }
        }
    }

    private func row(_ event: MFLCalendarOccurrence) -> some View {
        NavigationLink(value: CalendarEventRoute(id: event.id)) {
            HStack(spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: event.kind.symbol).font(.system(size: 22)).foregroundStyle(Color.blitzGreen).frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: event.kind.symbol).font(.system(size: 24)).foregroundStyle(Color.blitzGreen).accessibilityHidden(true)
                    }
                    Text(event.displayTitle).font(.headline)
                    Text(event.start.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                if calendar.preferences.lead(for: event) != nil {
                    Image(systemName: "bell.fill").foregroundStyle(.secondary).font(.caption).accessibilityLabel("Reminder enabled")
                }
            }.padding(.vertical, 4)
        }.accessibilityIdentifier("calendar-event-\(event.id)")
    }
}

struct CalendarEventRoute: Hashable { let id: String }

struct LeagueCalendarEventView: View {
    @Environment(AppModel.self) private var app
    let calendar: LeagueCalendarModel
    let eventID: String
    @State private var showingReminder = false
    @State private var showingInfo = false
    @State private var exportEvent: EventExportSelection?
    @State private var exportError: String?
    private var event: MFLCalendarOccurrence? { calendar.feed.snapshot?.events.first { $0.id == eventID } }

    var body: some View {
        List {
            if let error = calendar.feed.errorMessage ?? exportError {
                Label(error, systemImage: "wifi.exclamationmark").font(.subheadline).foregroundStyle(.secondary)
            }
            if let event {
                Section {
                    Label(event.displayTitle, systemImage: event.kind.symbol).font(.title3.bold())
                    LabeledContent("When", value: event.start.formatted(date: .complete, time: .shortened))
                    if let end = event.end, end > event.start { LabeledContent("Ends", value: end.formatted(date: .abbreviated, time: .shortened)) }
                }
                Section {
                    if let destination = event.kind.destination, let title = event.kind.actionTitle, let scope = app.browseScope {
                        NavigationLink(value: TeamToolsRoute(scope: scope, destination: destination)) { Label(title, systemImage: event.kind.symbol) }
                    }
                    Button {
                        showingReminder = true
                    } label: {
                        Label(calendar.preferences.lead(for: event)?.title ?? "Remind me", systemImage: calendar.preferences.lead(for: event) == nil ? "bell.badge" : "bell.fill")
                    }.disabled(event.start <= Date()).accessibilityIdentifier("calendar-remind-me")
                    Button("Add to Apple Calendar", systemImage: "calendar.badge.plus") {
                        Task {
                            exportError = nil
                            await calendar.refresh(force: true)
                            guard calendar.feed.errorMessage == nil, let fresh = self.event,
                                  fresh.start == event.start, fresh.end == event.end else {
                                exportError = "This event couldn’t be verified or its time changed. Review the latest date before copying it."; return
                            }
                            exportEvent = EventExportSelection(event: fresh)
                        }
                    }.disabled(app.isDemo || calendar.feed.isLoading)
                }
                if event.kind == .addsOpen || event.kind == .addsClose {
                    Text("Player locks and your league’s add/drop rules still apply.").font(.footnote).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            } else if calendar.feed.isLoading {
                ProgressView("Checking event…").frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("Event no longer available", systemImage: "calendar.badge.exclamationmark",
                    description: Text("It may have changed on MFL. Open Calendar for current league dates."))
            }
        }
        .navigationTitle("League event").navigationBarTitleDisplayMode(.inline)
        .task { await calendar.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Calendar information", systemImage: "info.circle") { showingInfo = true }
                    .popover(isPresented: $showingInfo) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("League dates").font(.headline)
                            Text("Published by MFL. Times use \(TimeZone.current.localizedName(for: .generic, locale: .current) ?? TimeZone.current.identifier).")
                            Text("Reminders follow the last updated league calendar. Apple Calendar receives a one-time copy, not a synced event.")
                        }.font(.subheadline).padding().frame(idealWidth: 300).presentationCompactAdaptation(.popover)
                    }
            }
        }
        .sheet(isPresented: $showingReminder) { if let event { EventReminderSheet(calendar: calendar, event: event) } }
        .sheet(item: $exportEvent) { selection in AppleCalendarEventEditor(event: selection.event) }
    }
}

private struct EventReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let calendar: LeagueCalendarModel
    let event: MFLCalendarOccurrence
    @State private var lead = ReminderLead.hour
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(event.displayTitle).font(.headline)
                    Text(event.start.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    ForEach(ReminderLead.allCases) { choice in
                        Button {
                            lead = choice
                        } label: {
                            HStack {
                                Text(choice.title).foregroundStyle(.primary)
                                Spacer()
                                if lead == choice { Image(systemName: "checkmark") }
                            }.frame(minHeight: 32)
                        }.disabled(event.start.addingTimeInterval(-Double(choice.rawValue)) <= Date())
                    }
                } footer: { Text("Past reminder times are unavailable.") }
                Section {
                    if calendar.preferences.lead(for: event) != nil {
                        Button("Turn off reminder") { Task { if await calendar.setEvent(event.id, choice: .off) { dismiss() } } }
                    }
                    if calendar.permission == .denied {
                        Button("Open iOS Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                    }
                    if let notice = calendar.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                }
            }.disabled(calendar.isSaving)
            .navigationTitle("Remind me").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(calendar.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enable") {
                        Task { if await calendar.setEvent(event.id, choice: .before(lead)) { dismiss() } }
                    }.disabled(calendar.isSaving || event.start.addingTimeInterval(-Double(lead.rawValue)) <= Date())
                        .accessibilityIdentifier("calendar-enable-reminder")
                }
            }
            .onAppear { lead = calendar.preferences.lead(for: event) ?? .hour; calendar.notice = nil }
            .interactiveDismissDisabled(calendar.isSaving)
        }.presentationDetents([.medium, .large])
    }
}

private struct DeadlineReminderSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let calendar: LeagueCalendarModel
    var body: some View {
        Form {
            Section {
                ForEach([LeagueEventKind.waivers, .addsOpen, .addsClose, .trades], id: \.self) { kind in
                    Picker(kind.title, selection: Binding(get: { calendar.preferences.categories[kind] }, set: { value in
                        Task { await calendar.setCategory(kind, lead: value) }
                    })) {
                        Text("Off").tag(ReminderLead?.none)
                        ForEach(ReminderLead.allCases) { Text($0.title).tag(Optional($0)) }
                    }.disabled(calendar.isSaving)
                }
            } header: { Text("Upcoming events") } footer: {
                Text("Individual event settings take priority. Reminders cover the next 14 days and refresh when you open Blitz.")
            }
            if let date = calendar.feed.snapshot?.fetchedAt { Text(ScheduleFreshness.label(updatedAt: date, now: Date())).font(.footnote).foregroundStyle(.secondary) }
            if let notice = calendar.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            if calendar.permission == .denied {
                Button("Open iOS Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            }
        }
        .navigationTitle("Reminders").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(calendar.isSaving) } }
    }
}

private struct EventExportSelection: Identifiable { let id = UUID(); var event: MFLCalendarOccurrence }

private struct AppleCalendarEventEditor: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let event: MFLCalendarOccurrence
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let editor = EKEventEditViewController()
        let store = EKEventStore()
        editor.eventStore = store
        let item = EKEvent(eventStore: store)
        item.title = event.displayTitle
        item.startDate = event.start
        item.endDate = event.end ?? event.start
        item.notes = "Copied from the MFL league calendar. This event does not update automatically."
        editor.event = item
        editor.editViewDelegate = context.coordinator
        return editor
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let close: () -> Void
        init(close: @escaping () -> Void) { self.close = close }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { close() }
    }
}
