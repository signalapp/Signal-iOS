//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class MessageProcessingOperation: OWSOperation {

    public override func run() {
        Logger.debug("")

        firstly(on: .global()) {
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.done { _ in
            Logger.verbose("Complete.")
            self.reportSuccess()
        }.catch { error in
            owsFailDebug("Error: \(error)")
            self.reportError(SSKUnretryableError.messageProcessingFailed)
        }
    }
}
