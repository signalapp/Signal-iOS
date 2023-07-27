//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWSRecordTranscriptJob {
    @objc
    static func archiveSessions(for address: SignalServiceAddress?, transaction: SDSAnyWriteTransaction) {
        guard let address else { return }

        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
        sessionStore.archiveAllSessions(for: address, tx: transaction.asV2Write)
    }
}
