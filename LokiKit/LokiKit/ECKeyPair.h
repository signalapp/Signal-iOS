@import Curve25519Kit;

@interface ECKeyPair (ECKeyPairExtension)

/// Based on `ECKeyPair.generateKeyPair()`.
+ (nonnull ECKeyPair *)generateKeyPairWithHexEncodedPrivateKey:(nonnull NSString *)hexEncodedPrivateKey;

@end
