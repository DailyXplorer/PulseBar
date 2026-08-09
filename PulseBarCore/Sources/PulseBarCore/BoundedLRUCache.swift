public final class BoundedLRUCache<Key: Hashable, Value> {
    public let capacity: Int

    private final class Node {
        let key: Key
        var value: Value
        weak var previous: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private var nodes: [Key: Node] = [:]
    private var mostRecent: Node?
    private var leastRecent: Node?

    public var count: Int {
        nodes.count
    }

    public init(capacity: Int) {
        precondition(capacity > 0, "BoundedLRUCache capacity must be positive.")
        self.capacity = capacity
    }

    public func value(forKey key: Key) -> Value? {
        guard let node = nodes[key] else {
            return nil
        }

        moveToMostRecent(node)
        return node.value
    }

    public func insert(_ value: Value, forKey key: Key) {
        if let existingNode = nodes[key] {
            existingNode.value = value
            moveToMostRecent(existingNode)
            return
        }

        if nodes.count == capacity, let leastRecent {
            remove(leastRecent)
        }

        let node = Node(key: key, value: value)
        nodes[key] = node
        insertAsMostRecent(node)
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        guard let node = nodes[key] else {
            return nil
        }

        let value = node.value
        remove(node)
        return value
    }

    public func removeAll() {
        nodes.removeAll(keepingCapacity: false)
        mostRecent = nil
        leastRecent = nil
    }

    private func moveToMostRecent(_ node: Node) {
        guard mostRecent !== node else {
            return
        }

        detach(node)
        insertAsMostRecent(node)
    }

    private func insertAsMostRecent(_ node: Node) {
        node.previous = nil
        node.next = mostRecent
        mostRecent?.previous = node
        mostRecent = node

        if leastRecent == nil {
            leastRecent = node
        }
    }

    private func remove(_ node: Node) {
        detach(node)
        nodes[node.key] = nil
    }

    private func detach(_ node: Node) {
        let previous = node.previous
        let next = node.next

        if let previous {
            previous.next = next
        } else {
            mostRecent = next
        }

        if let next {
            next.previous = previous
        } else {
            leastRecent = previous
        }

        node.previous = nil
        node.next = nil
    }
}
