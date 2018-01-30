//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeySendingErrorMessage.h"
#import "OWSFingerprint.h"
#import "OWSIdentityManager.h"
#import "PreKeyBundle+jsonDict.h"
#import "SignalRecipient.h"
#import "TSContactThread.h"
#import "TSErrorMessage_privateConstructor.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager+SessionStore.h"
#import <AxolotlKit/NSData+keyVersionByte.h>

NS_ASSUME_NONNULL_BEGIN

NSString *TSInvalidPreKeyBundleKey = @"TSInvalidPreKeyBundleKey";
NSString *TSInvalidRecipientKey = @"TSInvalidRecipientKey";

@interface TSInvalidIdentityKeySendingErrorMessage ()

@property (nonatomic, readonly) PreKeyBundle *preKeyBundle;

@end

@implementation TSInvalidIdentityKeySendingErrorMessage

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message
                               inThread:(TSThread *)thread
                           forRecipient:(NSString *)recipientId
                           preKeyBundle:(PreKeyBundle *)preKeyBundle
{
    // We want the error message to appear after the message.
    self = [super initWithTimestamp:message.timestamp + 1
                           inThread:thread
                  failedMessageType:TSErrorMessageWrongTrustedIdentityKey
                        recipientId:recipientId];

    if (self) {
        _messageId    = message.uniqueId;
        _preKeyBundle = preKeyBundle;
    }

    return self;
}

- (void)acceptNewIdentityKey
{
    // Shouldn't really get here, since we're no longer creating blocking SN changes.
    // But there may still be some old unaccepted SN errors in the wild that need to be accepted.
    OWSFail(@"accepting new identity key is deprecated.");

    // Saving a new identity mutates the session store so it must happen on the sessionStoreQueue
    NSData *_Nullable newIdentityKey = self.newIdentityKey;
    if (!newIdentityKey) {
        OWSFail(@"newIdentityKey is unexpectedly nil. Bad Prekey bundle?: %@", self.preKeyBundle);
        return;
    }

    [TSStorageManager.protocolStoreDBConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [[OWSIdentityManager sharedManager] saveRemoteIdentity:newIdentityKey
                                                       recipientId:self.recipientId
                                                   protocolContext:transaction];
        }];
}

- (nullable NSData *)newIdentityKey
{
    return [self.preKeyBundle.identityKey removeKeyType];
}

- (NSString *)theirSignalId
{
    return self.recipientId;
}

@end

NS_ASSUME_NONNULL_END
