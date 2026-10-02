/// The models held in memory, most recently used first, never more than
/// `capacity`. Pure bookkeeping (no engine calls) so the eviction rule is
/// unit-testable; `SapientChatService` stores its sessions in one.
nonisolated struct LoadedSlots<Session> {
    /// At most this many models stay loaded together.
    static var defaultCapacity: Int { 2 }

    let capacity: Int
    private(set) var entries: [(model: String, session: Session)] = []

    init(capacity: Int = Self.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// Loaded models, most recently used first.
    var models: [String] { entries.map(\.model) }

    /// The session for `model`, marking it most recently used.
    mutating func use(_ model: String) -> Session? {
        guard let index = entries.firstIndex(where: { $0.model == model }) else { return nil }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        return entry.session
    }

    /// Adds `model` as most recently used. Returns the models released to
    /// stay within capacity (least recently used first out).
    @discardableResult
    mutating func insert(_ model: String, session: Session) -> [String] {
        entries.removeAll { $0.model == model }
        entries.insert((model, session), at: 0)
        var released: [String] = []
        while entries.count > capacity {
            released.append(entries.removeLast().model)
        }
        return released
    }

    mutating func remove(_ model: String) {
        entries.removeAll { $0.model == model }
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}
