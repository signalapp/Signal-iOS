//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

extension TSInfoMessage {
    static func makeForPhoneNumberChange(
        thread: TSThread,
        timestamp: UInt64 = MessageTimestampGenerator.sharedInstance.generateTimestamp(),
        aci: Aci,
        oldNumber: String?,
        newNumber: E164?
    ) -> TSInfoMessage {
        var infoMessageUserInfo: [InfoMessageUserInfoKey: Any] = [
            .changePhoneNumberAciString: aci.serviceIdUppercaseString
        ]
        if let oldNumber {
            infoMessageUserInfo[.changePhoneNumberOld] = oldNumber
        }
        if let newNumber {
            infoMessageUserInfo[.changePhoneNumberNew] = newNumber.stringValue
        }

        let infoMessage = TSInfoMessage(
            thread: thread,
            messageType: .phoneNumberChange,
            timestamp: timestamp,
            infoMessageUserInfo: infoMessageUserInfo
        )
        infoMessage.wasRead = true

        return infoMessage
    }
}

public extension TSInfoMessage {
    struct PhoneNumberChangeInfo {
        public let aci: Aci
        /// This may be missing, for example on info messages from a backup.
        public let oldNumber: String?
        /// This may be missing, for example on info messages from a backup.
        public let newNumber: String?

        fileprivate init(aci: Aci, oldNumber: String?, newNumber: String?) {
            self.aci = aci
            self.oldNumber = oldNumber
            self.newNumber = newNumber
        }
    }

    func phoneNumberChangeInfo() -> PhoneNumberChangeInfo? {
        guard
            let infoMessageUserInfo,
            let aciString = infoMessageUserInfo[.changePhoneNumberAciString] as? String,
            let aci = Aci.parseFrom(aciString: aciString)
        else { return nil }

        return PhoneNumberChangeInfo(
            aci: aci,
            oldNumber: infoMessageUserInfo[.changePhoneNumberOld] as? String,
            newNumber: infoMessageUserInfo[.changePhoneNumberNew] as? String
        )
    }

    @objc
    func phoneNumberChangeInfoAci() -> AciObjC? {
        guard let aci = phoneNumberChangeInfo()?.aci else { return nil }
        return AciObjC(aci)
    }
}
