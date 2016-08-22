//
//  TSInvalidIdentityKeyErrorMessage.h
//  Signal
//
//  Created by Frederic Jacobs on 31/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

@interface TSInvalidIdentityKeyReceivingErrorMessage : TSInvalidIdentityKeyErrorMessage

+ (instancetype)untrustedKeyWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                         withTransaction:(YapDatabaseReadWriteTransaction *)transaction;
- (NSData *)newIdentityKey;

@end
