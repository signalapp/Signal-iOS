//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalServiceKit

/**
 * Manages the series of network requests and state changes required to provision
 * a linked device.
 *
 * At time of writing, despite appearing superficially similar, this class does **not**
 * mirror RegistrationCoordinator. This class does not deal at all with UI or steps
 * that require user input; it simply completes the sequence of mutations and
 * requests required behind the scenes for a device to be fully provisioned
 * _after_ it received a provisioning proto message from the primary device.
 *
 * See ProvisioningController for the sequence of UI steps that lead up to
 * this point.
 *
 * Eventually, it would be nice to mirror RegistrationCoordinator and have this
 * class behave like a state machine that handles the preceding steps as well.
 */
public protocol ProvisioningCoordinator {

    func completeProvisioning(
        provisionMessage: ProvisionMessage,
        deviceName: String
    ) async -> CompleteProvisioningResult
}

public enum CompleteProvisioningResult {
    case success
    /// This device was previously linked (or was previously a registered primary)
    /// but the new linking was being done with a different account, which is disallowed.
    case previouslyLinkedWithDifferentAccount
    /// The server told us the app or OS is obsolete and needs updating.
    case obsoleteLinkedDeviceError
    /// The server told us the number of devices on the account has exceeded the limit.
    case deviceLimitExceededError(DeviceLimitExceededError)
    case genericError(Error)
}
