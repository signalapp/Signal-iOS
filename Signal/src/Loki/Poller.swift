import PromiseKit

@objc public final class Poller : NSObject {
    private var isStarted = false
    private var currentJob: Promise<Void>?

    // MARK: Configuration
    private static let interval: TimeInterval = 60
    
    // MARK: Initialization
    @objc public static let shared = Poller()
    
    private override init() { }
    
    // MARK: General
    @objc public func startIfNeeded() {
        guard !isStarted else { return }
        Timer.scheduledTimer(timeInterval: Poller.interval, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        isStarted = true
    }
    
    @objc private func poll() {
        guard currentJob == nil else { return }
        currentJob = AppEnvironment.shared.messageFetcherJob.run().ensure { [weak self] in self?.currentJob = nil }
    }
}
