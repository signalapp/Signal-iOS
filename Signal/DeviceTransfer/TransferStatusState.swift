//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum TransferState {
    case idle
    case starting
    case connecting
    case transferring(Double)
    case done
    case error(Error)

    // TODO: [Backups] - Update/Localize these labels
    var label: String {
        switch self {
        case .idle:
            return ""
        case .starting:
            return "Starting..."
        case .connecting:
            return "Connecting..."
        case .transferring(let progress):
            let string = progress.formatted(.percent.precision(.fractionLength(2)))
            return "Transferring: \(string)"
        case .done:
            return "Finished!"
        case .error(let error):
            return "Error: \(error)"
        }
    }
}

class TransferStatusViewModel: ObservableObject {
    @Published var state: TransferState = .idle
    var onCancel: (() -> Void) = {}
    var onSuccess: (() -> Void) = {}
}
