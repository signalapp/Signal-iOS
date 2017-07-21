//
//  TSInvalidIdentityKeyErrorMessage.h
//  Signal
//
//  Created by Frederic Jacobs on 15/02/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSFingerprint;

@interface TSInvalidIdentityKeyErrorMessage : TSErrorMessage

- (void)acceptNewIdentityKey;
- (NSData *)newIdentityKey;
- (NSString *)theirSignalId;

@end

NS_ASSUME_NONNULL_END
