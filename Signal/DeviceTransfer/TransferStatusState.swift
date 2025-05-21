//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

enum TransferState {
    case idle
    case starting
    case connecting
    case transferring(Double)
    case done
    case error(Error)
}

class TransferStatusViewModel: ObservableObject {
    enum ViewState {
        enum Indefinite {
            case starting
            case connecting

            func title(isNewDevice: Bool) -> String {
                switch self {
                case .starting:
                    if isNewDevice {
                        "Waiting to connect to old iPhone…" // TODO: Localize
                    } else {
                        "Waiting to connect to new iPhone…" // TODO: Localize
                    }
                case .connecting:
                    if isNewDevice {
                        "Connecting to old iPhone…" // TODO: Localize
                    } else {
                        "Connecting to new iPhone…" // TODO: Localize
                    }
                }
            }

            func message(isNewDevice: Bool) -> String {
                if isNewDevice {
                    "Bring your old device nearby, and make sure Wi-Fi and Bluetooth are enabled." // TODO: Localize
                } else {
                    "Bring your new device nearby, and make sure Wi-Fi and Bluetooth are enabled." // TODO: Localize
                }
            }
        }
        case indefinite(Indefinite)
        case transferring(Double)
    }

    @Published var viewState: ViewState = .indefinite(.starting)
    var state: TransferState = .idle {
        didSet {
            switch state {
            case .idle, .starting:
                viewState = .indefinite(.starting)
            case .connecting:
                viewState = .indefinite(.connecting)
            case .transferring(let progress):
                viewState = .transferring(progress)
                self.progressDidUpdate(currentProgress: progress)
            case .done:
                viewState = .transferring(1)
            case .error(_):
                return
            }
        }
    }

    var onCancel: (() -> Void) = {}
    var onSuccess: (() -> Void) = {}

    // Take up space so it doesn't pop in when appearing
    @Published var progressEstimateLabel = " "
    private var throughputTimer: Timer?
    private var throughput: Double?
    private func progressDidUpdate(currentProgress: Double) {
        guard throughputTimer == nil else { return }
        var previouslyCompletedPortion = currentProgress
        throughputTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] timer in
            guard let self, case let .transferring(progress) = self.state else {
                self?.throughput = nil
                self?.progressEstimateLabel = " "
                timer.invalidate()
                self?.throughputTimer = nil
                return
            }

            let progressOverLastSecond = progress - previouslyCompletedPortion
            let remainingPortion = 1 - progress
            previouslyCompletedPortion = progress

            let estimatedTimeRemaining: TimeInterval
            if let throughput {
                // Give more weight to the existing average than the new value
                // to smooth changes in throughput and estimated time remaining.
                let newAverageThroughput = 0.2 * progressOverLastSecond + 0.8 * throughput
                self.throughput = newAverageThroughput
                estimatedTimeRemaining = remainingPortion / newAverageThroughput
            } else {
                self.throughput = progressOverLastSecond
                estimatedTimeRemaining = remainingPortion / progressOverLastSecond
            }

            self.progressEstimateLabel = timeEstimateFormatter.string(from: estimatedTimeRemaining) ?? " "
        }
    }

    private let timeEstimateFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.includesApproximationPhrase = true
        formatter.includesTimeRemainingPhrase = true
        return formatter
    }()
}

#if DEBUG
extension TransferStatusViewModel {
    @MainActor
    func simulateProgressForPreviews() async throws {
        state = .starting
        try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
        state = .connecting
        try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
        state = .transferring(0)
        var progress: Double = 0
        while progress < 1 {
            progress += 0.011
            state = .transferring(progress)
            try await Task.sleep(nanoseconds: UInt64.random(in: 60...120) * NSEC_PER_MSEC)
        }
        state = .done
        onSuccess()
    }
}
#endif
