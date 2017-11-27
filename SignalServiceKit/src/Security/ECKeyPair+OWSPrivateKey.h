//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Curve25519Kit/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

@interface ECKeyPair (OWSPrivateKey)

- (NSData *)ows_privateKey;

@end

NS_ASSUME_NONNULL_END
