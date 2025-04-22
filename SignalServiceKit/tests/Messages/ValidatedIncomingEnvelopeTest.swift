//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct ValidatedIncomingEnvelopeTest {
    @Test
    func testWrongDestination() throws {
        let localIdentifiers: LocalIdentifiers = .forUnitTests
        let sourceAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000000")
        let destinationAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")

        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: 1234)
        envelopeBuilder.setServerTimestamp(2345)
        envelopeBuilder.setType(.ciphertext)
        envelopeBuilder.setSourceServiceID(sourceAci.serviceIdString)
        envelopeBuilder.setSourceDevice(1)
        envelopeBuilder.setServerGuid(UUID().uuidString)
        envelopeBuilder.setDestinationServiceID(destinationAci.serviceIdString)
        let envelopeProto = try envelopeBuilder.build()
        #expect(throws: MessageProcessingError.wrongDestinationUuid, performing: {
            try ValidatedIncomingEnvelope(envelopeProto, localIdentifiers: localIdentifiers)
        })
    }
}
