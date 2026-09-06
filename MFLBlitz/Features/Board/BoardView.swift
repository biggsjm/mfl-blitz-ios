import SwiftUI

struct BoardView: View {
    @Environment(AppModel.self) private var model
    @State private var composerMode: MessageComposerView.Mode?

    var body: some View {
        List {
            if model.isDemo {
                DemoBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } else if !model.canPostToBoard {
                LiveWriteSafetyBanner(message: "Posting is unavailable")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if model.unconfirmedBoardPost != nil { UnconfirmedPostSection() }

            if !model.savedBoardDrafts.isEmpty {
                Section("Drafts") {
                    ForEach(model.savedBoardDrafts) { saved in
                        Button {
                            if let threadID = saved.threadID {
                                composerMode = .reply(threadID: threadID, subject: replySubject(threadID))
                            } else { composerMode = .newThread }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text").foregroundStyle(Color.blitzGreen)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draftTitle(saved)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(saved.draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? "Continue writing" : saved.draft.body)
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: BlitzMetrics.minimumTapTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Resume draft, \(draftTitle(saved))")
                        .accessibilityIdentifier("board-draft-\(saved.id)")
                    }
                }
            }

            if model.boardThreads.isEmpty && model.isLoadingBoard {
                ProgressView("Loading the league board…")
                    .listRowBackground(Color.clear)
            } else if model.boardThreads.isEmpty {
                EmptyState(title: "Quiet huddle", message: "The next league message will appear here.", systemImage: "bubble.left.and.bubble.right")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(model.boardThreads) { thread in
                        NavigationLink(value: thread.id) {
                            ThreadRow(thread: thread)
                        }
                    }
                } header: {
                    Text("MFL message board")
                } footer: {
                    Text("Posts stay on your league’s existing MFL board, so nobody needs another chat account.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Board")
        .navigationDestination(for: String.self) { threadID in
            if let thread = model.boardThreads.first(where: { $0.id == threadID }) {
                ThreadDetailView(threadID: thread.id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New thread", systemImage: "square.and.pencil") { composerMode = .newThread }
                    .disabled(!model.canPostToBoard)
            }
        }
        .sheet(item: $composerMode) { mode in
            MessageComposerView(mode: mode)
        }
        .refreshable { await model.refreshAll() }
    }

    private func replySubject(_ threadID: String) -> String {
        model.boardThreads.first { $0.id == threadID }?.subject ?? "Thread \(threadID)"
    }

    private func draftTitle(_ saved: SavedBoardDraft) -> String {
        if let threadID = saved.threadID { return "Reply: \(replySubject(threadID))" }
        let subject = saved.draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? "New thread" : subject
    }
}

private struct ThreadRow: View {
    let thread: BoardThread

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(thread.isUnread ? Color.blitzGreen : Color.clear)
                .frame(width: 9, height: 9)
                .overlay { Circle().stroke(.secondary.opacity(thread.isUnread ? 0 : 0.35)) }
                .padding(.top, 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.subject)
                        .font(.body.weight(thread.isUnread ? .bold : .semibold))
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Text(thread.lastActivity, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(thread.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    Text(thread.author)
                    Spacer()
                    Label("\(thread.replyCount)", systemImage: "bubble.left")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(thread.isUnread ? "Unread. " : "")\(thread.subject), by \(thread.author), \(thread.replyCount) replies, updated \(thread.lastActivity.formatted(.relative(presentation: .named)))")
    }
}

private struct ThreadDetailView: View {
    @Environment(AppModel.self) private var model
    let threadID: String
    @State private var showingReply = false

    private var thread: BoardThread? {
        model.boardThreads.first(where: { $0.id == threadID })
    }

    var body: some View {
        Group {
            if let thread {
                List {
                    Section {
                        ForEach(thread.posts) { post in
                            PostRow(post: post)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await model.loadThread(id: threadID) }
                .navigationTitle(thread.subject)
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    Button {
                        showingReply = true
                    } label: {
                        Label(model.boardDraft(threadID: threadID).hasContent ? "Resume reply" : "Reply to thread",
                              systemImage: "arrowshape.turn.up.left.fill")
                            .font(.headline)
                            .foregroundStyle(Color.blitzNavy)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.blitzGreen, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("board-reply-\(threadID)")
                    .disabled(!model.canPostToBoard)
                    .opacity(model.canPostToBoard ? 1 : 0.45)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial)
                }
                .sheet(isPresented: $showingReply) {
                    MessageComposerView(mode: .reply(threadID: thread.id, subject: thread.subject))
                }
                .task(id: threadID) {
                    await model.loadThread(id: threadID)
                }
            } else {
                EmptyState(title: "Thread unavailable", message: "Pull to refresh the message board.", systemImage: "bubble.left")
            }
        }
    }
}

private struct PostRow: View {
    let post: BoardPost

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: post.isUser ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.title2)
                .foregroundStyle(post.isUser ? Color.blitzGreen : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(post.author).font(.subheadline.bold())
                    Spacer()
                    Text(post.postedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(post.body)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

struct MessageComposerView: View {
    enum Mode: Identifiable {
        case newThread
        case reply(threadID: String, subject: String)

        var id: String {
            if case .reply(let threadID, _) = self { return threadID }
            return "new"
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var subject = ""
    @State private var bodyText = ""
    @FocusState private var bodyFocused: Bool
    @State private var loadedDraft = false
    @State private var showingCloseChoice = false
    @State private var isClosing = false
    @State private var editingScope: String?
    @State private var draftError: String?

    private var threadID: String? {
        if case .reply(let id, _) = mode { return id }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.unconfirmedBoardPost != nil { UnconfirmedPostSection() }
                if case .newThread = mode {
                    Section("Subject") {
                        TextField("What’s the topic?", text: $subject)
                            .textInputAutocapitalization(.sentences)
                    }
                } else if case .reply(_, let existingSubject) = mode {
                    Section("Replying to") { Text(existingSubject).font(.headline) }
                }

                Section("Message") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                        .focused($bodyFocused)
                        .accessibilityLabel("Message body")
                }

                if let draftError {
                    Section {
                        Label(draftError, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }

                Section {
                    Label("Visible to your league when posted.", systemImage: "person.2")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.isBusy)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        bodyFocused = false
                        if hasContent { showingCloseChoice = true }
                        else { finishDraft(save: false) }
                    }
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("board-composer-close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task {
                            let didPost: Bool
                            switch mode {
                            case .newThread:
                                didPost = await model.post(subject: subject, body: bodyText)
                            case .reply(let threadID, _):
                                didPost = await model.post(subject: nil, body: bodyText, threadID: threadID)
                            }
                            if didPost {
                                isClosing = true
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid || model.isBusy || model.isLoadingBoard || !model.canPostToBoard || model.unconfirmedBoardPost != nil)
                }
            }
            .onAppear {
                guard !loadedDraft else { return }
                let draft = model.boardDraft(threadID: threadID)
                editingScope = model.workspace?.storageScope
                subject = draft.subject
                bodyText = draft.body
                loadedDraft = true
                bodyFocused = true
            }
            .onChange(of: subject) { _, _ in saveDraft() }
            .onChange(of: bodyText) { _, _ in saveDraft() }
            .onChange(of: model.boardDraftRevision) { _, _ in
                let saved = model.boardDraft(threadID: threadID)
                subject = saved.subject
                bodyText = saved.body
            }
            .alert("Save draft?", isPresented: $showingCloseChoice) {
                Button("Save draft") { finishDraft(save: true) }
                Button("Discard draft", role: .destructive) { finishDraft(save: false) }
                Button("Keep editing", role: .cancel) { bodyFocused = true }
            } message: {
                Text("Continue later from Drafts on Board.")
            }
            .interactiveDismissDisabled(model.isBusy || hasContent)
        }
    }

    private func saveDraft() {
        guard loadedDraft, !isClosing, editingScope == model.workspace?.storageScope else { return }
        draftError = model.saveBoardDraft(subject: subject, body: bodyText, threadID: threadID)
            ? nil : "Couldn’t save your draft. Keep this open and try again."
    }

    private func finishDraft(save: Bool) {
        guard !model.isBusy, editingScope == model.workspace?.storageScope else { return }
        let succeeded = save
            ? model.saveBoardDraft(subject: subject, body: bodyText, threadID: threadID)
            : model.discardBoardDraft(threadID: threadID)
        guard succeeded else {
            draftError = "Couldn’t update your draft. Keep this open and try again."
            return
        }
        // Queued field changes must not recreate a discarded or posted draft.
        isClosing = true
        dismiss()
    }

    private var hasContent: Bool { BoardDraft(subject: subject, body: bodyText).hasContent }

    private var title: String {
        if case .newThread = mode { return "New thread" }
        return "Reply"
    }

    private var isValid: Bool {
        let hasBody = !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if case .newThread = mode {
            return hasBody && !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return hasBody
    }
}

private struct UnconfirmedPostSection: View {
    @Environment(AppModel.self) private var model
    @State private var showingAcknowledgment = false

    var body: some View {
        Section("Post awaiting confirmation") {
            if let pending = model.unconfirmedBoardPost {
                Text(pending.subject ?? "Reply").font(.subheadline.bold())
                Text(pending.body).font(.subheadline).lineLimit(3).foregroundStyle(.secondary)
            }
            Text("MFL may have received your last post. Sending is paused to prevent a duplicate, and your draft is kept.")
                .font(.subheadline)
            Button("Check MFL without sending again") { Task { await model.checkUnconfirmedPost() } }
            if let url = model.workspace?.leagueURL { Link("Open the MFL board to verify", destination: url) }
            Button("I checked MFL · resolve this warning") { showingAcknowledgment = true }
        }
        .disabled(model.isBusy)
        .confirmationDialog("Allow another post?", isPresented: $showingAcknowledgment, titleVisibility: .visible) {
            Button("I verified the board · allow posting") { Task { await model.acknowledgeUnconfirmedPost() } }
            Button("Keep checking", role: .cancel) {}
        } message: {
            Text("Only continue after checking MFL. If the previous message already exists, do not send the saved draft again.")
        }
    }
}
