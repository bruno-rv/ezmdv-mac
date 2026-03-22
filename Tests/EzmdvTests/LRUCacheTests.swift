import Testing
@testable import EzmdvCore

@Suite("LRUCache")
struct LRUCacheTests {

    @Test func getReturnsStoredValue() {
        var cache = LRUCache<String, String>(capacity: 5)
        cache.set("a", "alpha")
        #expect(cache.get("a") == "alpha")
    }

    @Test func getMissingKeyReturnsNil() {
        var cache = LRUCache<String, String>(capacity: 5)
        #expect(cache.get("missing") == nil)
    }

    @Test func evictsLRUEntryWhenAtCapacity() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", 1)
        cache.set("b", 2)
        cache.set("c", 3)
        // "a" is now LRU; inserting "d" should evict "a"
        cache.set("d", 4)
        #expect(cache["a"] == nil, "LRU entry 'a' should have been evicted")
        #expect(cache["b"] == 2)
        #expect(cache["c"] == 3)
        #expect(cache["d"] == 4)
    }

    @Test func getUpdatesLRUOrder() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", 1)
        cache.set("b", 2)
        cache.set("c", 3)
        // Access "a" to promote it; "b" becomes LRU
        _ = cache.get("a")
        cache.set("d", 4)  // should evict "b", not "a"
        #expect(cache["a"] != nil, "'a' was recently accessed and should not be evicted")
        #expect(cache["b"] == nil, "'b' should be evicted as LRU")
    }

    @Test func remove() {
        var cache = LRUCache<String, String>(capacity: 5)
        cache.set("x", "ex")
        cache.remove("x")
        #expect(cache["x"] == nil)
        #expect(cache.count == 0)
    }

    @Test func countReflectsInsertionsAndEvictions() {
        var cache = LRUCache<Int, Int>(capacity: 3)
        #expect(cache.count == 0)
        cache.set(1, 10); cache.set(2, 20); cache.set(3, 30)
        #expect(cache.count == 3)
        cache.set(4, 40)  // evicts entry 1
        #expect(cache.count == 3)
    }

    @Test func overwriteDoesNotGrowBeyondCapacity() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", 1); cache.set("b", 2)
        cache.set("a", 99)  // update existing — no eviction
        #expect(cache.count == 2)
        #expect(cache["a"] == 99)
        #expect(cache["b"] == 2)
    }

    @Test func capacityOne() {
        var cache = LRUCache<String, Int>(capacity: 1)
        cache.set("a", 1)
        cache.set("b", 2)
        #expect(cache["a"] == nil)
        #expect(cache["b"] == 2)
        #expect(cache.count == 1)
    }
}
