//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// There is a naming conflict between ``SignalServiceKit.ServiceId`` and
/// ``LibSignalClient.ServiceId``. This typealias makes it such that unqualified
/// uses of `ServiceId` refer to the `SignalServiceKit` type.
public typealias ServiceId = SignalServiceKit.ServiceId
