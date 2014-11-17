#import <Foundation/Foundation.h>

/// All dependencies on external libraries used for cryptography should be hidden behind CryptoTools methods.
/// That way, changing to a different library affects only one part of the system.

@interface CryptoTools : NSObject

/// Returns a secure random 16-bit unsigned integer.
+ (uint16_t)generateSecureRandomUInt16;

/// Returns a secure random 32-bit unsigned integer.
+ (uint32_t)generateSecureRandomUInt32;

/// Returns data composed of 'length' cryptographically unpredictable bytes sampled uniformly from [0, 256).
+ (NSData*)generateSecureRandomData:(NSUInteger)length;

/// Returns the token included as part of HTTP OTP authentication.
+ (NSString*)computeOTPWithPassword:(NSString*)password andCounter:(int64_t)counter;

@end
