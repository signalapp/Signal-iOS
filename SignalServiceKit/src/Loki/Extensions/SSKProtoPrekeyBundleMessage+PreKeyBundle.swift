public extension SSKProtoPrekeyBundleMessage {
    
    @objc public var preKeyBundle: PreKeyBundle? {
        let registrationId = TSAccountManager.sharedInstance().getOrGenerateRegistrationId()
        return PreKeyBundle(registrationId: Int32(registrationId),
                            deviceId: Int32(self.deviceID),
                            preKeyId: Int32(self.prekeyID),
                            preKeyPublic: self.prekey,
                            signedPreKeyPublic: self.signedKey,
                            signedPreKeyId: Int32(self.signedKeyID),
                            signedPreKeySignature: self.signature,
                            identityKey: self.identityKey)
    }
    
    @objc public class func builder(fromPreKeyBundle preKeyBundle: PreKeyBundle) -> SSKProtoPrekeyBundleMessageBuilder {
        let builder = self.builder()
        
        builder.setIdentityKey(preKeyBundle.identityKey)
        builder.setPrekeyID(UInt32(preKeyBundle.preKeyId))
        builder.setPrekey(preKeyBundle.preKeyPublic)
        builder.setSignedKeyID(UInt32(preKeyBundle.signedPreKeyId))
        builder.setSignedKey(preKeyBundle.signedPreKeyPublic)
        builder.setSignature(preKeyBundle.signedPreKeySignature)
        
        return builder
    }
}
