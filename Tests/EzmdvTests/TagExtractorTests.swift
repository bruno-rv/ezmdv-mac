import Testing
@testable import EzmdvCore

@Suite("TagExtractor")
struct TagExtractorTests {

    @Test func basicTag() {
        #expect(TagExtractor.findTags(in: "This is #todo") == ["todo"])
    }

    @Test func multipleTagsSorted() {
        let tags = TagExtractor.findTags(in: "#todo and #project-x and #urgent")
        #expect(tags == ["project-x", "todo", "urgent"])
    }

    @Test func tagsAreLowercased() {
        let tags = TagExtractor.findTags(in: "#TODO #MyTag")
        #expect(tags == ["mytag", "todo"])
    }

    @Test func duplicatesAreDeduped() {
        let tags = TagExtractor.findTags(in: "#todo and again #todo")
        #expect(tags == ["todo"])
    }

    @Test func pureNumericHashIsNotATag() {
        let tags = TagExtractor.findTags(in: "Issue #123 is not a tag")
        #expect(tags == [])
    }

    @Test func tagInsideWordIsIgnored() {
        // "color#tag" — # preceded by word char, should not match
        let tags = TagExtractor.findTags(in: "color#tag should not match")
        #expect(tags == [])
    }

    @Test func tagAtStartOfLine() {
        let tags = TagExtractor.findTags(in: "#inbox\n#processed")
        #expect(tags == ["inbox", "processed"])
    }

    @Test func tagWithHyphen() {
        let tags = TagExtractor.findTags(in: "#project-alpha #work-in-progress")
        #expect(tags == ["project-alpha", "work-in-progress"])
    }

    @Test func tagWithUnderscore() {
        let tags = TagExtractor.findTags(in: "#my_tag #another_one")
        #expect(tags == ["another_one", "my_tag"])
    }

    @Test func emptyStringReturnsNoTags() {
        #expect(TagExtractor.findTags(in: "") == [])
    }

    @Test func noTagsInPlainText() {
        #expect(TagExtractor.findTags(in: "No tags here.") == [])
    }

    @Test func resultIsSorted() {
        let tags = TagExtractor.findTags(in: "#zebra #apple #mango")
        #expect(tags == ["apple", "mango", "zebra"])
    }
}
