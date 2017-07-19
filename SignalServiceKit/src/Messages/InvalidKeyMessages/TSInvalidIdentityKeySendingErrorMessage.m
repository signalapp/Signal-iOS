//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeySendingErrorMessage.h"
#import "OWSFingerprint.h"
#import "OWSIdentityManager.h"
#import "PreKeyBundle+jsonDict.h"
#import "SignalRecipient.h"
#import "TSContactThread.h"
#import "TSErrorMessage_privateConstructor.h"
#import "TSOutgoingMessage.h"
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
    self = [super initWithTimestamp:message.timestamp
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
    dispatch_async([OWSDispatch sessionStoreQueue], ^{
        [[OWSIdentityManager sharedManager] saveRemoteIdentity:self.newIdentityKey recipientId:self.recipientId];
    });
}

- (NSData *)newIdentityKey
{
    return [self.preKeyBundle.identityKey removeKeyType];
}

- (NSString *)theirSignalId
{
    return self.recipientId;
}

@end

NS_ASSUME_NONNULL_END
