import CryptoKit
import Darwin
import Foundation

@objc(BPTimedDispatch)
public final class BPTimedDispatch: NSObject, @unchecked Sendable {
    private var scheduledBlock: (() -> Void)?
    private var dispatchTimer: Timer?
    private var dispatchQueue: DispatchQueue = .main

    @objc(scheduleDispatchAfterTimeInterval:ofBlock:)
    public func scheduleDispatch(afterTimeInterval interval: TimeInterval, of block: @escaping () -> Void) {
        scheduleDispatch(afterTimeInterval: interval, in: .main, of: block)
    }

    @objc(scheduleDispatchAfterTimeInterval:inQueue:ofBlock:)
    public func scheduleDispatch(afterTimeInterval interval: TimeInterval, in queue: DispatchQueue, of block: @escaping () -> Void) {
        scheduledBlock = block
        dispatchQueue = queue
        dispatchTimer?.invalidate()
        dispatchTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(dispatchBlockTimerDidFire(_:)),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func dispatchBlockTimerDidFire(_ sender: Timer) {
        nonisolated(unsafe) let localBlock = scheduledBlock
        scheduledBlock = nil
        let queue = dispatchQueue
        queue.async {
            localBlock?()
        }
    }
}
