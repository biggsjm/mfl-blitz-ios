import SwiftUI

struct BoardView: View {
    @Environment(AppModel.self) private var model
    @State private var showingComposer = false

    var body: some View {
        List {
            if model.isDemo {
                DemoBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } else if !model.canSubmitChanges {
                LiveWriteSafetyBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if model.boardThreads.isEmpty {
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
                Button("New thread", systemImage: "square.and.pencil") { showingComposer = true }
                    .disabled(!model.canSubmitChanges)
            }
        }
        .sheet(isPresented: $showingComposer) {
            MessageComposerView(mode: .newThread)
        }
        .refreshable { await model.refreshAll() }
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
                .navigationTitle(thread.subject)
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    Button {
                        showingReply = true
                    } label: {
                        Label("Reply to thread", systemImage: "arrowshape.turn.up.left.fill")
                            .font(.headline)
                            .foregroundStyle(Color.blitzNavy)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.blitzGreen, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canSubmitChanges)
                    .opacity(model.canSubmitChanges ? 1 : 0.45)
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
    enum Mode {
        case newThread
        case reply(threadID: String, subject: String)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var subject = ""
    @State private var bodyText = ""
    @FocusState private var bodyFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Label("Your post is sent to the existing MFL message board and will be visible to league members.", systemImage: "person.2")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid || model.isBusy)
                }
            }
            .onAppear { bodyFocused = true }
        }
    }

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
