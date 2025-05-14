//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie
import SwiftUI
import SignalUI
import SignalServiceKit

class OutgoingDeviceRestoreProgressViewController: HostingController<TransferStatusView> {
    init(viewModel: TransferStatusViewModel) {
        super.init(wrappedView: TransferStatusView(viewModel: viewModel))
        view.backgroundColor = UIColor.Signal.background
        modalPresentationStyle = .overFullScreen
    }
    var prefersNavigationBarHidden: Bool { true }
}

#if DEBUG
@available(iOS 17, *)
#Preview {
    {
        let viewModel = TransferStatusViewModel()
        viewModel.state = .starting
        return OutgoingDeviceRestoreProgressViewController(viewModel: viewModel)
    }()
}
#endif
