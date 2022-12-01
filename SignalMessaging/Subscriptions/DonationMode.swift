//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents the modes in which a user might donate to Signal.
public enum DonationMode: CaseIterable {
    /// A one-time donation, or "boost".
    case oneTime
    /// A recurring monthly donation, or "subscription".
    case monthly
    /// A one-time donation (boost), whose resulting badge is associated with
    /// another user.
    case gift
}
