//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// MARK: - RegistrationTransferStatusPresenter

protocol RegistrationTransferStatusPresenter: AnyObject {
    func cancelTransfer()
    func transferFailed(error: Error)
}

class RegistrationDeviceTransferStatusViewController: DeviceTransferStatusViewController {
    init(
        coordinator: DeviceTransferCoordinator,
        presenter: RegistrationTransferStatusPresenter? = nil
    ) {
        super.init(coordinator: coordinator)

        coordinator.cancelTransferBlock = {
            presenter?.cancelTransfer()
        }

        coordinator.onFailure = { error in
            presenter?.transferFailed(error: error)
        }
    }
}
