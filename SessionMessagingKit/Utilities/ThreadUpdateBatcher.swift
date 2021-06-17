
final class ThreadUpdateBatcher {
    private var threadIDs: Set<String> = []

    private lazy var timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.touch() }

    static let shared = ThreadUpdateBatcher()

    private init() {
        DispatchQueue.main.async {
            SessionUtilitiesKit.touch(self.timer)
        }
    }

    deinit { timer.invalidate() }

    func touch(_ threadID: String) {
        threadIDs.insert(threadID)
    }

    @objc private func touch() {
        let threadIDs = self.threadIDs
        self.threadIDs.removeAll()
        Storage.write { transaction in
            for threadID in threadIDs {
                guard let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return }
                thread.touch(with: transaction)
            }
        }
    }
}
