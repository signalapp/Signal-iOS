//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension BackupArchive {

    /// An address to refer to a contact in a backup.
    /// At least one of the three fields is guaranteed to be present.
    struct ContactAddress {
        let aci: Aci?
        let pni: Pni?
        let e164: E164?

        // MARK: - Failable Initializers

        init?(aci: Aci?, pni: Pni?, e164: E164?) {
            guard aci != nil || pni != nil || e164 != nil else {
                return nil
            }
            self.aci = aci
            self.pni = pni
            self.e164 = e164
        }

        init?(aci: Aci?, pni: Pni?) {
            guard aci != nil || pni != nil else {
                return nil
            }
            self.aci = aci
            self.pni = pni
            self.e164 = nil
        }

        init?(aci: Aci?, e164: E164?) {
            guard aci != nil || e164 != nil else {
                return nil
            }
            self.aci = aci
            self.pni = nil
            self.e164 = e164
        }

        init?(pni: Pni?, e164: E164?) {
            guard pni != nil || e164 != nil else {
                return nil
            }
            self.aci = nil
            self.pni = pni
            self.e164 = e164
        }

        // MARK: - Non-Failable Initializers

        init(aci: Aci, pni: Pni?, e164: E164?) {
            self.aci = aci
            self.pni = pni
            self.e164 = e164
        }

        init(aci: Aci, pni: Pni) {
            self.aci = aci
            self.pni = pni
            self.e164 = nil
        }

        init(aci: Aci, e164: E164) {
            self.aci = aci
            self.pni = nil
            self.e164 = e164
        }

        init(pni: Pni, e164: E164) {
            self.aci = nil
            self.pni = pni
            self.e164 = e164
        }

        init(aci: Aci) {
            self.aci = aci
            self.pni = nil
            self.e164 = nil
        }

        init(pni: Pni) {
            self.aci = nil
            self.pni = pni
            self.e164 = nil
        }

        init(e164: E164) {
            self.aci = nil
            self.pni = nil
            self.e164 = e164
        }

        // MARK: - ServiceId convenience

        init?(serviceId: ServiceId?, e164: E164?) {
            let aci = serviceId as? Aci
            let pni = serviceId as? Pni
            self.init(aci: aci, pni: pni, e164: e164)
        }

        init(serviceId: ServiceId, e164: E164) {
            switch serviceId.concreteType {
            case .aci(let aci):
                self.aci = aci
                self.pni = nil
            case .pni(let pni):
                self.aci = nil
                self.pni = pni
            }
            self.e164 = e164
        }

        init(serviceId: ServiceId) {
            switch serviceId.concreteType {
            case .aci(let aci):
                self.aci = aci
                self.pni = nil
            case .pni(let pni):
                self.aci = nil
                self.pni = pni
            }
            self.e164 = nil
        }
    }
}

extension BackupArchive.ContactAddress {

    func asSignalServiceAddress() -> SignalServiceAddress {
        return SignalServiceAddress(serviceId: aci ?? pni, e164: e164)
    }

    func asArchivingAddress() -> BackupArchive.RecipientArchivingContext.Address {
        return .contact(self)
    }

    func asRestoringAddress() -> BackupArchive.RecipientRestoringContext.Address {
        return .contact(self)
    }
}

extension SignalServiceAddress {

    /// Warning: when using this method, you will get an aci or a pni but not both, even if we
    /// know both. This is because the SignalServiceAddress only keeps one.
    /// If you want an aci and a pni in the ContactAddress, construct it from the SignalRecipient.
    func asSingleServiceIdBackupAddress() -> BackupArchive.ContactAddress? {
        return .init(
            aci: serviceId as? Aci,
            pni: serviceId as? Pni,
            e164: e164,
        )
    }
}
