//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie
import SignalServiceKit
import SignalUI
import SwiftUI

class OutgoingDeviceRestoreProgressViewController: HostingController<TransferStatusView> {
    init(viewModel: TransferStatusViewModel) {
        super.init(wrappedView: TransferStatusView(viewModel: viewModel, isNewDevice: false))
        view.backgroundColor = UIColor.Signal.background
        modalPresentationStyle = .overFullScreen
    }

    override var prefersNavigationBarHidden: Bool { true }
}

#if DEBUG
@available(iOS 17, *)
#Preview {
    let viewModel = TransferStatusViewModel()
    Task { try? await viewModel.simulateProgressForPreviews() }
    return OutgoingDeviceRestoreProgressViewController(viewModel: viewModel)
}
#endif
