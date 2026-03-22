import Foundation

/// A fixed-capacity Least-Recently-Used cache backed by a dictionary + access-order array.
/// Value semantics (struct with mutating methods) — plays nicely with @Published.
public struct LRUCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var accessOrder: [Key] = []
    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "LRUCache capacity must be positive")
        self.capacity = capacity
    }

    /// Returns the value for `key` and marks it as most-recently used.
    public mutating func get(_ key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    /// Stores `value` for `key`. Evicts the least-recently-used entry when at capacity.
    public mutating func set(_ key: Key, _ value: Value) {
        if storage[key] == nil {
            while accessOrder.count >= capacity {
                let evict = accessOrder.removeFirst()
                storage.removeValue(forKey: evict)
            }
            accessOrder.append(key)
        } else {
            touch(key)
        }
        storage[key] = value
    }

    /// Removes a key from the cache.
    public mutating func remove(_ key: Key) {
        storage.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
    }

    /// Non-mutating read (does not update LRU order). Use for existence checks only.
    public subscript(key: Key) -> Value? { storage[key] }

    public var count: Int { storage.count }

    private mutating func touch(_ key: Key) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
}
