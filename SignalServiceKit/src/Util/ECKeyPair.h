@import Curve25519Kit;

@interface ECKeyPair (ECKeyPairExtension)

+ (nonnull ECKeyPair *)generateKeyPairWithHexEncodedPrivateKey:(nonnull NSString *)hexEncodedPrivateKey;

@end
