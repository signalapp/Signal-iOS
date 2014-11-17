#import "CryptoTools.h"

#import <openssl/hmac.h>

#import "Constraints.h"
#import "NSData+Conversions.h"
#import "EvpMessageDigest.h"
#import "EvpSymetricUtil.h"
#import "Util.h"
#import "NSData+CryptoTools.h"

@implementation CryptoTools

+ (NSData*)generateSecureRandomData:(NSUInteger)length {
    NSMutableData* d = [NSMutableData dataWithLength:length];
    SecRandomCopyBytes(kSecRandomDefault, length, [d mutableBytes]);
    return d;
}

+ (uint16_t)generateSecureRandomUInt16 {
    return [[self generateSecureRandomData:sizeof(uint16_t)] bigEndianUInt16At:0];
}

+ (uint32_t)generateSecureRandomUInt32 {
    return [[self generateSecureRandomData:sizeof(uint32_t)] bigEndianUInt32At:0];
}

+ (NSString*)computeOTPWithPassword:(NSString*)password andCounter:(int64_t)counter {
    require(password != nil);
    
    NSData* d = [[@(counter) stringValue] encodedAsUtf8];
    NSData* h = [d hmacWithSHA1WithKey:[password encodedAsUtf8]];
    return [h encodedAsBase64];
}

@end

