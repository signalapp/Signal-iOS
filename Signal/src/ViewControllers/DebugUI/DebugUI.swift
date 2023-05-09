//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

func shouldUseDebugUI() -> Bool {
#if USE_DEBUG_UI
    return true
#else
    return false
#endif
}

func showDebugUIForThread(_ thread: TSThread, fromViewController: UIViewController) {
#if USE_DEBUG_UI
    DebugUITableViewController.presentDebugUIForThread(thread, from: fromViewController)
#else
    owsFailDebug("Debug UI not enabled.")
#endif
}
