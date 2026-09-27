//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class LocalFileBackupAttachmentRestoreProgressObserver {
    private weak var progress: LocalFileBackupAttachmentRestoreProgress?
    fileprivate let id: UUID = UUID()
    fileprivate let block: (OWSProgress) -> Void

    fileprivate init(progress: LocalFileBackupAttachmentRestoreProgress?, block: @escaping (OWSProgress) -> Void) {
        self.progress = progress
        self.block = block
    }

    deinit {
        progress?.removeObserver(id)
    }
}

public class LocalFileBackupAttachmentRestoreProgress {
    private struct State {
        var observers: WeakArray<LocalFileBackupAttachmentRestoreProgressObserver> = []
        var sink: OWSProgressSink?
        var source: OWSProgressSource?
        var latestProgress: OWSProgress?
    }

    private let state: AtomicValue<State>

    public init() {
        self.state = AtomicValue(State(), lock: .init())
    }

    public func addObserver(_ block: @escaping (OWSProgress) -> Void) -> LocalFileBackupAttachmentRestoreProgressObserver {
        let (observer, latestProgress) = state.update { _state in
            let observer = LocalFileBackupAttachmentRestoreProgressObserver(progress: self, block: block)
            _state.observers.append(observer)
            return (observer, _state.latestProgress)
        }
        if let latestProgress { block(latestProgress) }
        return observer
    }

    public func beginObserving(totalByteCount: UInt64) {
        state.update { _state in
            _state.sink = nil
            _state.source = nil
            _state.latestProgress = nil

            guard totalByteCount > 0 else { return }
            let sink = OWSProgress.createSink { [weak self] progress in
                self?.update(progress)
            }
            _state.sink = sink
            _state.source = sink.addSource(withLabel: "restore", unitCount: totalByteCount)
        }
    }

    public func didProcessAttachment(unencryptedByteCount: UInt32) {
        state.update { _state in
            _state.source?.incrementCompletedUnitCount(by: UInt64(unencryptedByteCount))
        }
    }

    public func didFinish() {
        let completeProgress: OWSProgress? = state.update { _state in
            _state.sink = nil
            _state.source = nil
            guard let total = _state.latestProgress?.totalUnitCount else { return nil }
            return OWSProgress(completedUnitCount: total, totalUnitCount: total)
        }
        if let completeProgress { update(completeProgress) }
    }

    private func update(_ progress: OWSProgress) {
        let observers = state.update { _state in
            _state.latestProgress = progress
            return _state.observers.elements
        }
        observers.forEach { $0.block(progress) }
    }

    func removeObserver(_ id: UUID) {
        state.update { _state in
            _state.observers.removeAll(where: { $0.id == id })
        }
    }
}
