//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MessageProcessingOperation: OWSOperation {

    // MARK: - Dependencies

    private var messageProcessing: MessageProcessing {
        return SSKEnvironment.shared.messageProcessing
    }

    // MARK: - 

    public override func run() {
        Logger.debug("")

        firstly(on: .global()) {
            self.messageProcessing.allMessageFetchingAndProcessingPromise()
        }.done { _ in
            Logger.verbose("Complete.")
            self.reportSuccess()
        }.catch { error in
            owsFailDebug("Error: \(error)")
            self.reportError(error.asUnretryableError)
        }
    }
}
