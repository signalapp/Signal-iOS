//
//  TSInvalidIdentityKeySendingErrorMessage.h
//  Signal
//
//  Created by Frederic Jacobs on 15/02/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"
#import "TSOutgoingMessage.h"

@class PreKeyBundle;

@interface TSInvalidIdentityKeySendingErrorMessage : TSInvalidIdentityKeyErrorMessage

#define TSInvalidPreKeyBundleKey @"TSInvalidPreKeyBundleKey"
#define TSInvalidRecipientKey @"TSInvalidRecipientKey"

+ (instancetype)untrustedKeyWithOutgoingMessage:(TSOutgoingMessage *)outgoingMessage
                                       inThread:(TSThread *)thread
                                   forRecipient:(NSString *)recipientId
                                   preKeyBundle:(PreKeyBundle *)preKeyBundle
                                withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

- (NSString *)recipientId;

@end
