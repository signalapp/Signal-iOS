//
//  TSInvalidIdentityKeyErrorMessage.h
//  Signal
//
//  Created by Frederic Jacobs on 31/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"

@interface TSInvalidIdentityKeyErrorMessage : TSErrorMessage

+ (instancetype)untrustedKeyWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction;

- (void)acceptNewIdentityKey;
- (NSString*)newIdentityKey;

@end
