public extension SSKProtoPrekeyBundleMessage {
    
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
