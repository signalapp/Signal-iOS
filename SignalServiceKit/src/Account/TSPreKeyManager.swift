//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MessageProcessingOperation: OWSOperation {

    // MARK: - Dependencies

    private var messageProcessor: MessageProcessor {
        return SSKEnvironment.shared.messageProcessor
    }

    // MARK: - 

    public override func run() {
        Logger.debug("")

        firstly(on: .global()) {
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.done { _ in
            Logger.verbose("Complete.")
            self.reportSuccess()
        }.catch { error in
            owsFailDebug("Error: \(error)")
            self.reportError(error.asUnretryableError)
        }
    }
}
