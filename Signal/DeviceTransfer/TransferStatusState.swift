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
    case cancelled
    case error(DeviceTransferService.Error)
}

class TransferStatusViewModel: ObservableObject {
    enum ViewState {
        enum Indefinite {
            case starting
            case connecting
            case cancelling

            func title(isNewDevice: Bool) -> String {
                switch self {
                case .starting:
                    if isNewDevice {
                        OWSLocalizedString(
                            "DEVICE_TRANSFER_STATUS_NEW_DEVICE_STARTING",
                            comment: "Status message on new device when transfer is starting."
                        )
                    } else {
                        OWSLocalizedString(
                            "DEVICE_TRANSFER_STATUS_OLD_DEVICE_STARTING",
                            comment: "Status message on old device when transfer is starting."
                        )
                    }
                case .connecting:
                    if isNewDevice {
                        OWSLocalizedString(
                            "DEVICE_TRANSFER_STATUS_NEW_DEVICE_CONNECTING",
                            comment: "Status message on new device when connecting to old device."
                        )
                    } else {
                        OWSLocalizedString(
                            "DEVICE_TRANSFER_STATUS_OLD_DEVICE_CONNECTING",
                            comment: "Status message on new device when connecting to new device."
                        )
                    }
                case .cancelling:
                    if isNewDevice {
                        OWSLocalizedString(
                            "DEVICE_TRANSFER_STATUS_NEW_DEVICE_CANCELLING",
                            comment: "Status message on new device when cancelling transfer."
                        )
                    } else {
                        OWSLocalizedString(
                            "DEVICE_TRANSFER_STATUS_OLD_DEVICE_CANCELLING",
                            comment: "Status message on old device when cancelling transfer."
                        )
                    }
                }
            }

            func message(isNewDevice: Bool) -> String {
                if isNewDevice {
                    OWSLocalizedString(
                        "DEVICE_TRANSFER_STATUS_NEW_DEVICE_CONNECTING_MESSAGE",
                        comment: "Description message on new device displayed during device transfer."
                    )
                } else {
                    OWSLocalizedString(
                        "DEVICE_TRANSFER_STATUS_OLD_DEVICE_CONNECTING_MESSAGE",
                        comment: "Description message on old device displayed during device transfer."
                    )
                }
            }
        }
        case indefinite(Indefinite)
        case transferring(Double)
        case error(Error)
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
            case .cancelled:
                viewState = .indefinite(.cancelling)
            case .error(let error):
                viewState = .error(error)
                return
            }
        }
    }

    var confirmCancellation: (() async -> Bool) = { return true }
    var cancelTransferBlock: (() -> Void) = {}
    var onSuccess: (() -> Void) = {}
    var onFailure: ((Error) -> Void) = { _ in }

    @MainActor
    func propmtUserToCancelTransfer() async {
        guard await confirmCancellation() else { return }
        cancelTransferBlock()
    }

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
