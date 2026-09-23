//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

public class MockAciContactShareNameManager: AciContactShareNameManager {
    private var mockNames: [SignalRecipient.RowId: AciContactShareName] = [:]

    public init() {}

    // MARK: AciContactShareNameManager

    public func fetchName(for recipient: SignalRecipient, tx: DBReadTransaction) -> AciContactShareName? {
        return mockNames[recipient.id]
    }

    public func saveName(
        givenName: String?,
        familyName: String?,
        for recipient: SignalRecipient,
        tx: DBWriteTransaction,
    ) {
        mockNames[recipient.id] = AciContactShareName(recipient: recipient, givenName: givenName, familyName: familyName)
    }

    public func deleteName(for recipient: SignalRecipient, tx: DBWriteTransaction) {
        mockNames[recipient.id] = nil
    }
}

#endif
