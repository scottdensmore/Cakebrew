import CryptoKit
import Darwin
import Foundation

@objc(BPSearchCoordinator)
public final class BPSearchCoordinator: NSObject, @unchecked Sendable {
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let performSearch: (String) -> Void
    private let cancelSearch: () -> Void

    @objc(isSearching) public private(set) var searching: Bool = false
    @objc public private(set) var originalSidebarRow: Int = 0
    @objc public private(set) var generation: UInt = 0

    @objc(initWithPerformSearch:cancelSearch:)
    public convenience init(performSearch: @escaping (String) -> Void, cancelSearch: @escaping () -> Void) {
        let timedDispatch = BPTimedDispatch()
        self.init(
            schedule: { delay, work in
                timedDispatch.scheduleDispatch(afterTimeInterval: delay, in: .main, of: work)
            },
            performSearch: performSearch,
            cancelSearch: cancelSearch
        )
    }

    @objc(initWithSchedule:performSearch:cancelSearch:)
    public init(schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
                performSearch: @escaping (String) -> Void,
                cancelSearch: @escaping () -> Void) {
        self.schedule = schedule
        self.performSearch = performSearch
        self.cancelSearch = cancelSearch
        super.init()
    }

    @objc(scheduleQuery:)
    public func scheduleQuery(_ query: String) {
        precondition(Thread.isMainThread, "Search coordination must run on the main thread")
        precondition(!query.isEmpty)
        let currentGeneration = self.generation
        schedule(0.15) { [weak self] in
            guard let self, currentGeneration == self.generation else { return }
            self.performSearch(query)
        }
    }

    @objc(didReceiveResultsForSidebarRow:)
    public func didReceiveResults(forSidebarRow row: Int) {
        precondition(Thread.isMainThread, "Search coordination must run on the main thread")
        if !searching {
            originalSidebarRow = row
        }
        searching = true
    }

    @discardableResult
    @objc(endSearchReturningSidebarRow)
    public func endSearchReturningSidebarRow() -> Int {
        precondition(Thread.isMainThread, "Search coordination must run on the main thread")
        generation &+= 1
        searching = false
        cancelSearch()
        return originalSidebarRow
    }

    @objc(cancelForNavigation)
    public func cancelForNavigation() {
        precondition(Thread.isMainThread, "Search coordination must run on the main thread")
        generation &+= 1
        searching = false
        cancelSearch()
    }
}
