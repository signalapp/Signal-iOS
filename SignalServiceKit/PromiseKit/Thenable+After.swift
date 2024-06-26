//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Guarantee where Value == Void {

    /// Uses `mach_absolute_time` (pauses while suspended)
    static func after(
        on scheduler: Scheduler? = nil,
        seconds: TimeInterval
    ) -> Guarantee<Void> {
        let (guarantee, future) = Guarantee<Void>.pending()

        // This check isn't *great* but there's no proper API for this. It's unlikely this suffix will
        // ever change and even if it does the consequence of getting it wrong is insignificant.
        let isAppExtension = Bundle.main.bundlePath.hasSuffix("appex")

        if isAppExtension && seconds > 2.0 {
            // App extensions have shorter lifecycles and are under more restrictive memory limits
            // For short-lived extensions (e.g. the NSE), the future make not resolve for a long time effectively
            // leaking any objects captured by the promise resolve block.
            //
            // If these show up repeatedly in the logs, it might be a good idea to move to the walltime variant.
            Logger.info("Building a time-elapsed guarantee with process-clock interval of: \(seconds)")
        }

        (scheduler ?? DispatchQueue.global()).asyncAfter(deadline: .now() + seconds) {
            future.resolve()
        }
        return guarantee
    }

    /// Uses `gettimeofday` (ticks while suspended)
    static func after(
        on scheduler: Scheduler? = nil,
        wallInterval: TimeInterval
    ) -> Guarantee<Void> {
        let (guarantee, future) = Guarantee<Void>.pending()
        (scheduler ?? DispatchQueue.global()).asyncAfter(wallDeadline: .now() + wallInterval) {
            future.resolve()
        }
        return guarantee
    }
}
