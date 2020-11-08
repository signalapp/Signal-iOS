#import <Foundation/Foundation.h>
#import <Curve25519Kit/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

@interface ECKeyPair (Utilities)

- (ECKeyPair *)initWithPublicKey:(NSData *)publicKey privateKey:(NSData *)privateKey;
- (NSData *)privateKey;

@end

NS_ASSUME_NONNULL_END
