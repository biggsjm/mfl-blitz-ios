import Foundation
import Testing
@testable import MFLBlitz

@MainActor
@Suite("Board draft save, resume and discard")
struct BoardDraftTests {
    @Test("Blank and whitespace composers do not create visible drafts")
    func blankDrafts() {
        let app = AppModel(repository: DemoLeagueRepository(), privateStore: MemoryPrivateStore())
        #expect(app.saveBoardDraft(subject: " \n", body: "\t ", threadID: nil))
        #expect(app.savedBoardDrafts.isEmpty)
        #expect(app.saveBoardDraft(subject: "Subject only", body: "", threadID: nil))
        #expect(app.savedBoardDrafts.map(\.id) == ["new"])
        #expect(app.saveBoardDraft(subject: "", body: "", threadID: nil))
        #expect(app.savedBoardDrafts.isEmpty)
    }

    @Test("New-thread and reply drafts restore independently; discard keeps other drafts")
    func restorationAndDiscard() async {
        let store = MemoryPrivateStore()
        let repository = ReliabilityRepository()
        let app = AppModel(repository: repository, privateStore: store)
        await app.signIn(credentials: LoginCredentials())
        #expect(app.saveBoardDraft(subject: "New topic", body: "New body", threadID: nil))
        #expect(app.saveBoardDraft(subject: "", body: "Reply one", threadID: "t1"))
        #expect(app.saveBoardDraft(subject: "", body: "Reply two", threadID: "t2"))
        #expect(app.savedBoardDrafts.map(\.id) == ["new", "t1", "t2"])
        #expect(app.savedBoardDrafts[1].threadID == "t1")
        #expect(app.discardBoardDraft(threadID: "t1"))
        let restored = AppModel(repository: repository, privateStore: store)
        await restored.restoreSession()
        #expect(restored.savedBoardDrafts.map(\.id) == ["new", "t2"])
        #expect(restored.boardDraft(threadID: "t2").body == "Reply two")
        await repository.changeTeam()
        let other = AppModel(repository: repository, privateStore: store)
        await other.restoreSession()
        #expect(other.savedBoardDrafts.isEmpty)
    }

    @Test("Failed secure writes cannot report a successful save or discard")
    func storageFailure() {
        let store = BoardFailingStore()
        let app = AppModel(repository: DemoLeagueRepository(), privateStore: store)
        app.isDemo = false
        #expect(app.saveBoardDraft(subject: "Keep", body: "Original", threadID: nil))
        store.setRejectWrites(true)
        #expect(!app.saveBoardDraft(subject: "Changed", body: "Unsaved", threadID: nil))
        #expect(!app.discardBoardDraft(threadID: nil))
        #expect(app.boardDraft(threadID: nil) == BoardDraft(subject: "Keep", body: "Original"))
        #expect(app.savedBoardDrafts.count == 1)
        store.setRejectWrites(false)
        #expect(app.discardBoardDraft(threadID: nil))
        #expect(app.savedBoardDrafts.isEmpty)
    }

    @Test("Confirmed posting clears only its draft and blank callbacks cannot recreate it")
    func postedDraft() async {
        let app = AppModel(repository: DemoLeagueRepository(), privateStore: MemoryPrivateStore())
        app.saveBoardDraft(subject: "Synthetic thread", body: "Synthetic post", threadID: nil)
        app.saveBoardDraft(subject: "", body: "Unsent reply", threadID: "t1")
        #expect(await app.post(subject: "Synthetic thread", body: "Synthetic post"))
        #expect(app.savedBoardDrafts.map(\.id) == ["t1"])
        app.saveBoardDraft(subject: "", body: "", threadID: nil)
        #expect(app.savedBoardDrafts.map(\.id) == ["t1"])
    }
}

private final class BoardFailingStore: PrivateStore, @unchecked Sendable {
    private let backing = MemoryPrivateStore()
    private let lock = NSLock()
    private var rejectsWrites = false
    func setRejectWrites(_ value: Bool) { lock.withLock { rejectsWrites = value } }
    func read(_ key: String) throws -> Data? { backing.read(key) }
    func write(_ data: Data, key: String) throws {
        if lock.withLock({ rejectsWrites }) { throw StoreError.unavailable }
        backing.write(data, key: key)
    }
    func remove(_ key: String) throws { backing.remove(key) }
}
