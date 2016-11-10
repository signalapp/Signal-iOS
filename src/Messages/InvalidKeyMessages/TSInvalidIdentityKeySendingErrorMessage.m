//  Created by Frederic Jacobs on 15/02/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.

#import "TSInvalidIdentityKeySendingErrorMessage.h"
#import "OWSFingerprint.h"
#import "PreKeyBundle+jsonDict.h"
#import "SignalRecipient.h"
#import "TSContactThread.h"
#import "TSErrorMessage_privateConstructor.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager+IdentityKeyStore.h"
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
                  failedMessageType:TSErrorMessageWrongTrustedIdentityKey];

    if (self) {
        _messageId    = message.uniqueId;
        _preKeyBundle = preKeyBundle;
        _recipientId  = recipientId;
    }

    return self;
}

+ (instancetype)untrustedKeyWithOutgoingMessage:(TSOutgoingMessage *)outgoingMessage
                                       inThread:(TSThread *)thread
                                   forRecipient:(NSString *)recipientId
                                   preKeyBundle:(PreKeyBundle *)preKeyBundle
{
    TSInvalidIdentityKeySendingErrorMessage *message = [[self alloc] initWithOutgoingMessage:outgoingMessage
                                                                                    inThread:thread
                                                                                forRecipient:recipientId
                                                                                preKeyBundle:preKeyBundle];
    return message;
}

- (void)acceptNewIdentityKey
{
    [[TSStorageManager sharedManager] saveRemoteIdentity:self.newIdentityKey recipientId:self.recipientId];
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
