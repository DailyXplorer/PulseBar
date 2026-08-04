import PulseBarCore
import Testing

@Test func boundedLRUCacheEvictsLeastRecentlyInsertedValue() {
    let cache = BoundedLRUCache<String, Int>(capacity: 2)
    cache.insert(1, forKey: "one")
    cache.insert(2, forKey: "two")
    cache.insert(3, forKey: "three")

    #expect(cache.value(forKey: "one") == nil)
    #expect(cache.value(forKey: "two") == 2)
    #expect(cache.value(forKey: "three") == 3)
    #expect(cache.count == 2)
}

@Test func boundedLRUCacheReadPromotesValue() {
    let cache = BoundedLRUCache<String, Int>(capacity: 2)
    cache.insert(1, forKey: "one")
    cache.insert(2, forKey: "two")

    #expect(cache.value(forKey: "one") == 1)

    cache.insert(3, forKey: "three")

    #expect(cache.value(forKey: "one") == 1)
    #expect(cache.value(forKey: "two") == nil)
    #expect(cache.value(forKey: "three") == 3)
}

@Test func boundedLRUCacheReplacementKeepsCountAndPromotesValue() {
    let cache = BoundedLRUCache<String, Int>(capacity: 2)
    cache.insert(1, forKey: "one")
    cache.insert(2, forKey: "two")
    cache.insert(10, forKey: "one")
    cache.insert(3, forKey: "three")

    #expect(cache.value(forKey: "one") == 10)
    #expect(cache.value(forKey: "two") == nil)
    #expect(cache.value(forKey: "three") == 3)
    #expect(cache.count == 2)
}

@Test func boundedLRUCacheRemovalAndClearUpdateCount() {
    let cache = BoundedLRUCache<String, Int>(capacity: 2)
    cache.insert(1, forKey: "one")
    cache.insert(2, forKey: "two")

    #expect(cache.removeValue(forKey: "one") == 1)
    #expect(cache.removeValue(forKey: "missing") == nil)
    #expect(cache.count == 1)

    cache.removeAll()

    #expect(cache.count == 0)
    #expect(cache.value(forKey: "two") == nil)
}
