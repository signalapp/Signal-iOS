//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Failed story send notifications check if the topmost view controller conforms
/// to this protocol.
/// In practice this is always ``MyStoriesViewController``, but that lives in
/// the Signal target and this needs to be checked in SignalMessaging.
public protocol FailedStorySendDisplayController: UIViewController {}
