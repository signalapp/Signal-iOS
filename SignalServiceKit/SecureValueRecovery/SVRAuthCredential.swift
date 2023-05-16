//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Changes the pointer to the SVR auth credential used in the rest of the app.
///
/// At first, we talk only to KBS (SVR1), and this credential just points to
/// KBSAuthCredential as a result.
///
/// Once support for SVR2 is added, we will talk to _both_ KBS and SVR2;
/// at that point this should point to OrchestratingSVRAuthCredential instead.
///
/// ~90 days later, we will stop talking to KBS entirely, and this should be changed
/// to point to SVR2AuthCredential.
public typealias SVRAuthCredential = KBSAuthCredential
