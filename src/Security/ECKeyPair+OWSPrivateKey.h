//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import <25519/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

@interface ECKeyPair (OWSPrivateKey)

- (NSData *)ows_privateKey;

@end

NS_ASSUME_NONNULL_END
