/// Bookkeeping for asynchronous encoder callbacks. Callers hold pipelineLock.
/// A reset retires old callbacks so they cannot release a new pipeline's slot.
struct EncodeWorkCounter {
    private(set) var count = 0
    private var epoch: UInt64 = 0

    mutating func begin() -> UInt64 {
        count += 1
        return epoch
    }

    func isCurrent(_ ticket: UInt64) -> Bool { ticket == epoch }

    mutating func finish(_ ticket: UInt64) {
        guard isCurrent(ticket) else { return }
        count = max(0, count - 1)
    }

    mutating func reset() {
        epoch &+= 1
        count = 0
    }
}
