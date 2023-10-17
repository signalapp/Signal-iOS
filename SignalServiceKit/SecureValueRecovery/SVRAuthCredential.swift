//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Changes the pointer to the SVR auth credential used in the rest of the app.
///
/// Currently we only talk to SVR2; eventually this may point to SVR3.
public typealias SVRAuthCredential = SVR2AuthCredential
