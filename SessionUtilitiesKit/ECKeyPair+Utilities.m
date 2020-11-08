#import "ECKeyPair+Utilities.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ECKeyPair (Utilities)

- (ECKeyPair *)initWithPublicKey:(NSData *)snPublicKey privateKey:(NSData *)snPrivateKey
{
    ECKeyPair *keyPair = [[ECKeyPair alloc] init];
    [keyPair setValue:snPublicKey forKey:@"publicKey"];
    [keyPair setValue:snPrivateKey forKey:@"privateKey"];
    return keyPair;
}

- (NSData *)privateKey
{
    return [NSData dataWithBytes:self->privateKey length:32];
}

@end

NS_ASSUME_NONNULL_END
