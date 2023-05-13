//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

protocol DebugUIPage {

    var name: String { get }

    func section(thread: TSThread?) -> OWSTableSection?
}

#endif
