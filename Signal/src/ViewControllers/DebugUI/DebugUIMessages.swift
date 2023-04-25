//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

#if DEBUG

@objc
public extension DebugUIMessages {
    static func anyIncomingSenderAddress(forThread thread: TSThread) -> SignalServiceAddress? {
        if let contactThread = thread as? TSContactThread {
            return contactThread.contactAddress
        } else if let groupThread = thread as? TSGroupThread {
            guard let localAddress = Self.tsAccountManager.localAddress else {
                owsFailDebug("Missing localAddress.")
                return nil
            }
            let members = groupThread.groupMembership.fullMembers
            let otherMembers = members.filter { $0 != localAddress }.shuffled()
            guard let anyOtherMember = otherMembers.first else {
                owsFailDebug("No other members.")
                return nil
            }
            return anyOtherMember
        } else {
            owsFailDebug("Invalid thread.")
            return nil
        }
    }

    static func processDecryptedEnvelope(_ envelope: SSKProtoEnvelope, plaintextData: Data) {
        messageProcessor.processFakeDecryptedEnvelope(envelope, plaintextData: plaintextData)
    }
}

// MARK: - Random text

extension DebugUIMessages {
    private static let shortTextLength: UInt = 4

    @objc
    static func randomShortText() -> String {
        let alphabet: [Character] = (97...122).map { (ascii: Int) in
            Character(Unicode.Scalar(ascii)!)
        }

        let chars: [Character] = (0..<shortTextLength).map { _ in
            let index = UInt.random(in: 0..<UInt(alphabet.count))
            return alphabet[Int(index)]
        }

        return String(chars)
    }
}

#endif
