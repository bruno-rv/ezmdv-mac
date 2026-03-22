import Testing
@testable import EzmdvCore
// NO import Foundation — critical to avoid _Testing_Foundation conflict with CLT Swift

@Suite("WikiLinkIndex")
struct WikiLinkIndexTests {

    // MARK: - Helpers

    private func makeIndex(_ files: [(path: String, name: String, content: String)]) -> WikiLinkIndex {
        WikiLinkIndex.build(files: files)
    }

    // MARK: - Tests

    @Test func basicBacklink() {
        // File A links to File B. B's backlinks should include A.
        let files: [(path: String, name: String, content: String)] = [
            (path: "/proj/a.md", name: "a", content: "See [[b]] for details."),
            (path: "/proj/b.md", name: "b", content: "I am B.")
        ]
        let index = makeIndex(files)
        let backlinks = index.backlinks(for: "b")
        #expect(backlinks.count == 1)
        #expect(backlinks[0].sourcePath == "/proj/a.md")
        #expect(backlinks[0].sourceName == "a")
        #expect(backlinks[0].linkText == "b")
    }

    @Test func multipleBacklinks() {
        // Files A and C both link to B. B should have 2 backlinks.
        let files: [(path: String, name: String, content: String)] = [
            (path: "/proj/a.md", name: "a", content: "Check [[b]] here."),
            (path: "/proj/b.md", name: "b", content: "I am B."),
            (path: "/proj/c.md", name: "c", content: "Also see [[b]] for more.")
        ]
        let index = makeIndex(files)
        let backlinks = index.backlinks(for: "b")
        #expect(backlinks.count == 2)
        let sources = backlinks.map(\.sourcePath).sorted()
        #expect(sources == ["/proj/a.md", "/proj/c.md"])
    }

    @Test func aliasedLink() {
        // [[target|display text]] should resolve to "target"
        let files: [(path: String, name: String, content: String)] = [
            (path: "/proj/a.md", name: "a", content: "Visit [[notes|my notes]] today."),
            (path: "/proj/notes.md", name: "notes", content: "Notes file.")
        ]
        let index = makeIndex(files)
        let backlinks = index.backlinks(for: "notes")
        #expect(backlinks.count == 1)
        #expect(backlinks[0].sourcePath == "/proj/a.md")
        // linkText preserves the raw inner content including the alias
        #expect(backlinks[0].linkText == "notes|my notes")
    }

    @Test func headingLink() {
        // [[target#heading]] should resolve to "target"
        let files: [(path: String, name: String, content: String)] = [
            (path: "/proj/a.md", name: "a", content: "See [[target#introduction]] for context."),
            (path: "/proj/target.md", name: "target", content: "# Introduction")
        ]
        let index = makeIndex(files)
        let backlinks = index.backlinks(for: "target")
        #expect(backlinks.count == 1)
        #expect(backlinks[0].sourcePath == "/proj/a.md")
        #expect(backlinks[0].linkText == "target#introduction")
    }

    @Test func outgoingLinks() {
        // File A links to B and C. outgoingLinks(from: A.path) should return both targets.
        let files: [(path: String, name: String, content: String)] = [
            (path: "/proj/a.md", name: "a", content: "See [[b]] and also [[c]]."),
            (path: "/proj/b.md", name: "b", content: "B"),
            (path: "/proj/c.md", name: "c", content: "C")
        ]
        let index = makeIndex(files)
        let outgoing = index.outgoingLinks(from: "/proj/a.md").sorted()
        #expect(outgoing == ["b", "c"])
    }

    @Test func caseInsensitive() {
        // [[MyNote]] should match a target queried as "mynote"
        let files: [(path: String, name: String, content: String)] = [
            (path: "/proj/a.md", name: "a", content: "Link to [[MyNote]] here."),
            (path: "/proj/mynote.md", name: "mynote", content: "My note content.")
        ]
        let index = makeIndex(files)
        // Query with lowercase — should find the link from A
        let backlinks = index.backlinks(for: "mynote")
        #expect(backlinks.count == 1)
        #expect(backlinks[0].sourcePath == "/proj/a.md")
        // Outgoing should also be stored normalized (lowercased)
        let outgoing = index.outgoingLinks(from: "/proj/a.md")
        #expect(outgoing == ["mynote"])
    }

    @Test func hasIncomingAndOutgoing() {
        // hasIncoming and hasOutgoing boolean helpers
        let files: [(path: String, name: String, content: String)] = [
            (path: "/proj/a.md", name: "a", content: "Points to [[b]]."),
            (path: "/proj/b.md", name: "b", content: "No outgoing links."),
            (path: "/proj/c.md", name: "c", content: "Isolated file.")
        ]
        let index = makeIndex(files)

        // A has outgoing links but nothing points to it
        #expect(index.hasOutgoing("/proj/a.md") == true)
        #expect(index.hasIncoming("a") == false)

        // B has an incoming link from A but no outgoing links
        #expect(index.hasIncoming("b") == true)
        #expect(index.hasOutgoing("/proj/b.md") == false)

        // C has neither
        #expect(index.hasIncoming("c") == false)
        #expect(index.hasOutgoing("/proj/c.md") == false)
    }

    @Test func emptyInput() {
        // build(files: []) should return an empty index without crashing
        let index = WikiLinkIndex.build(files: [])
        #expect(index.backlinks(for: "anything").isEmpty)
        #expect(index.outgoingLinks(from: "/proj/a.md").isEmpty)
        #expect(index.hasIncoming("anything") == false)
        #expect(index.hasOutgoing("/proj/a.md") == false)
    }
}
