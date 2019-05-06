#import "ECKeyPair.h"
#import <SignalCoreKit/OWSAsserts.h>

extern void curve25519_donna(unsigned char *output, const unsigned char *a, const unsigned char *b);

@implementation ECKeyPair (ECKeyPairExtension)

+ (nonnull ECKeyPair *)generateKeyPairWithHexEncodedPrivateKey:(nonnull NSString *)hexEncodedPrivateKey {
    NSMutableData *privateKey = [NSMutableData new];
    for (NSUInteger i = 0; i < hexEncodedPrivateKey.length; i += 2) {
        char buffer[3];
        buffer[0] = (char)[hexEncodedPrivateKey characterAtIndex:i];
        buffer[1] = (char)[hexEncodedPrivateKey characterAtIndex:i + 1];
        buffer[2] = '\0';
        unsigned char byte = (unsigned char)strtol(buffer, NULL, 16);
        [privateKey appendBytes:&byte length:1];
    }
    static const uint8_t basepoint[ECCKeyLength] = { 9 };
    NSMutableData *publicKey = [NSMutableData dataWithLength:ECCKeyLength];
    if (!publicKey) { OWSFail(@"Could not allocate buffer"); }
    curve25519_donna(publicKey.mutableBytes, privateKey.mutableBytes, basepoint);
    ECKeyPair *result = [ECKeyPair new];
    [result setValue:[privateKey copy] forKey:@"privateKey"];
    [result setValue:[publicKey copy] forKey:@"publicKey"];
    return result;
}

@end
