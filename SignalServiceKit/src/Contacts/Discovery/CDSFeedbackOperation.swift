//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

/*

 Is this still necessary?

class CDSFeedbackOperation: OWSOperation {

    enum FeedbackResult {
        case ok
        case mismatch
        case attestationError(reason: String)
        case unexpectedError(reason: String)
    }

    private let legacyRegisteredPhoneNumbers: Set<String>

    var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    // MARK: Initializers

    required init(legacyRegisteredPhoneNumbers: Set<String>) {
        self.legacyRegisteredPhoneNumbers = legacyRegisteredPhoneNumbers

        super.init()

        Logger.debug("")
    }

    // MARK: OWSOperation Overrides

    override func checkForPreconditionError() -> Error? {
        // override super with no-op
        // In this rare case, we want to proceed even though our dependency might have an
        // error so we can report the details of that error to the feedback service.
        return nil
    }

    // Called every retry, this is where the bulk of the operation's work should go.
    override func run() {

        guard !isCancelled else {
            Logger.info("no work to do, since we were canceled")
            self.reportCancelled()
            return
        }

        guard let cdsOperation = dependencies.first as? ContactDiscoveryOperation else {
            let error = OWSAssertionError("cdsOperation was unexpectedly nil")
            self.reportError(error)
            return
        }

        if let error = cdsOperation.failingError {
            switch error {
            case TSNetworkManagerError.failedConnection:
                // Don't submit feedback for connectivity errors
                self.reportSuccess()
            case ContactDiscoveryError.serverError, ContactDiscoveryError.clientError:
                // Server already has this information, no need submit feedback
                self.reportSuccess()
            case let raError as RemoteAttestationError:
                let reason = raError.reason
                switch raError.code {
                case .assertionError:
                    self.makeRequest(result: .unexpectedError(reason: "Remote Attestation assertionError: \(reason ?? "unknown")"))
                case .failed:
                    self.makeRequest(result: .attestationError(reason: "Remote Attestation failed: \(reason ?? "unknown")"))
                @unknown default:
                    self.makeRequest(result: .unexpectedError(reason: "Remote Attestation assertionError: unknown raError.code"))
                }
            case ContactDiscoveryError.assertionError(let assertionDescription):
                self.makeRequest(result: .unexpectedError(reason: "assertionError: \(assertionDescription)"))
            case ContactDiscoveryError.parseError(description: let parseErrorDescription):
                self.makeRequest(result: .unexpectedError(reason: "parseError: \(parseErrorDescription)"))
            default:
                let nsError = error as NSError
                let reason = "unexpectedError code:\(nsError.code)"
                self.makeRequest(result: .unexpectedError(reason: reason))
            }

            return
        }

        let modernResults = cdsOperation.registeredContacts ?? Set()

        let registeredPhoneNumbers = Set(modernResults.map { $0.e164PhoneNumber })

        if registeredPhoneNumbers == legacyRegisteredPhoneNumbers {
            self.makeRequest(result: .ok)
            return
        } else {
            self.makeRequest(result: .mismatch)
            return
        }
    }

    func makeRequest(result: FeedbackResult) {
        let reason: String?
        switch result {
        case .ok:
            reason = nil
        case .mismatch:
            reason = nil
        case .attestationError(let attestationErrorReason):
            reason = attestationErrorReason
        case .unexpectedError(let unexpectedErrorReason):
            reason = unexpectedErrorReason
        }
        let request = OWSRequestFactory.cdsFeedbackRequest(status: result.statusPath, reason: reason)
        self.networkManager.makeRequest(request,
                                        success: { _, _ in self.reportSuccess() },
                                        failure: { _, error in self.reportError(withUndefinedRetry: error) })
    }
}

extension CDSFeedbackOperation.FeedbackResult {
    var statusPath: String {
        switch self {
        case .ok:
            return "ok"
        case .mismatch:
            return "mismatch"
        case .attestationError:
            return "attestation-error"
        case .unexpectedError:
            return "unexpected-error"
        }
    }
}
*/
