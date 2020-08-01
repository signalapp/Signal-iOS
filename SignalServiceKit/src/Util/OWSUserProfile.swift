//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension OWSUserProfile {

    // The max bytes for a user's profile name, encoded in UTF8.
    // Before encrypting and submitting we NULL pad the name data to this length.
    static let kNameDataLength: UInt = 26

    // MARK: - Encryption

    @objc(encryptProfileData:profileKey:)
    class func encrypt(profileData: Data, profileKey: OWSAES256Key) -> Data? {
        assert(profileKey.keyData.count == kAES256_KeyByteLength)
        return Cryptography.encryptAESGCMProfileData(plainTextData: profileData, key: profileKey)
    }

    @objc(decryptProfileData:profileKey:)
    class func decrypt(profileData: Data, profileKey: OWSAES256Key) -> Data? {
        assert(profileKey.keyData.count == kAES256_KeyByteLength)
        return Cryptography.decryptAESGCMProfileData(encryptedData: profileData, key: profileKey)
    }

    @objc(decryptProfileNameData:profileKey:)
    class func decrypt(profileNameData: Data, profileKey: OWSAES256Key) -> PersonNameComponents? {
        guard let decryptedData = decrypt(profileData: profileNameData, profileKey: profileKey) else { return nil }

        // Unpad profile name. The given and family name are stored
        // in the string like "<given name><null><family name><null padding>"
        let nameSegments: [Data] = decryptedData.split(separator: 0x00)

        // Given name is required
        guard nameSegments.count > 0,
            let givenName = String(data: nameSegments[0], encoding: .utf8), !givenName.isEmpty else {
                owsFailDebug("unexpectedly missing first name")
                return nil
        }

        // Family name is optional
        let familyName: String?
        if nameSegments.count > 1 {
            familyName = String(data: nameSegments[1], encoding: .utf8)
        } else {
            familyName = nil
        }

        var nameComponents = PersonNameComponents()
        nameComponents.givenName = givenName
        nameComponents.familyName = familyName
        return nameComponents
    }

    @objc(encryptProfileNameComponents:profileKey:)
    class func encrypt(profileNameComponents: PersonNameComponents, profileKey: OWSAES256Key) -> Data? {
        guard var paddedNameData = profileNameComponents.givenName?.data(using: .utf8) else { return nil }
        if let familyName = profileNameComponents.familyName {
            // Insert a null separator
            paddedNameData.count += 1
            guard let familyNameData = familyName.data(using: .utf8) else { return nil }
            paddedNameData.append(familyNameData)
        }

        // Two names plus null separator.
        let totalNameLength = Int(kNameDataLength) * 2 + 1

        guard paddedNameData.count <= totalNameLength else { return nil }

        // All encrypted profile names should be the same length on the server,
        // so we pad out the length with null bytes to the maximum length.
        let paddingByteCount = totalNameLength - paddedNameData.count
        paddedNameData.count += paddingByteCount

        assert(paddedNameData.count == totalNameLength)

        return encrypt(profileData: paddedNameData, profileKey: profileKey)
    }
}
