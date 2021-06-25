//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension SignalAccount {
    @objc
    public func buildContactAvatarJpegData() -> Data? {
        guard let contact = self.contact else {
            return nil
        }
        guard !contact.isFromContactSync else {
            return nil
        }
        guard let cnContactId: String = contact.cnContactId else {
            owsFailDebug("Missing cnContactId.")
            return nil
        }
        guard let contactAvatarData = Self.contactsManager.avatarData(forCNContactId: cnContactId) else {
            return nil
        }
        guard let contactAvatarJpegData = UIImage.validJpegData(fromAvatarData: contactAvatarData) else { owsFailDebug("Could not convert avatar to JPEG.")
            return nil
        }
        return contactAvatarJpegData
    }
}
