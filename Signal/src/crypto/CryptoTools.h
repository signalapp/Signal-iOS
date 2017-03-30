//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

/// All dependencies on external libraries used for cryptography should be hidden behind CryptoTools methods.
/// That way, changing to a different library affects only one part of the system.

@interface CryptoTools : NSObject

/// Returns data composed of 'length' cryptographically unpredictable bytes sampled uniformly from [0, 256).
+ (NSData *)generateSecureRandomData:(NSUInteger)length;

@end
