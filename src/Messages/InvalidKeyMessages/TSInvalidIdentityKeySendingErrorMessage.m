//  Created by Frederic Jacobs on 15/02/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.

#import "TSInvalidIdentityKeySendingErrorMessage.h"
#import "OWSFingerprint.h"
#import "PreKeyBundle+jsonDict.h"
#import "SignalRecipient.h"
#import "TSContactThread.h"
#import "TSErrorMessage_privateConstructor.h"
#import "TSMessagesManager+sendMessages.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import <AxolotlKit/NSData+keyVersionByte.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSInvalidIdentityKeySendingErrorMessage ()

@property (nonatomic, readonly) PreKeyBundle *preKeyBundle;
@property (nonatomic, readonly) NSString *messageId;

@end

@implementation TSInvalidIdentityKeySendingErrorMessage

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message
                               inThread:(TSThread *)thread
                           forRecipient:(NSString *)recipientId
                           preKeyBundle:(PreKeyBundle *)preKeyBundle
                            transaction:(YapDatabaseReadWriteTransaction *)transaction {
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
                                withTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    TSInvalidIdentityKeySendingErrorMessage *message = [[self alloc] initWithOutgoingMessage:outgoingMessage
                                                                                    inThread:thread
                                                                                forRecipient:recipientId
                                                                                preKeyBundle:preKeyBundle
                                                                                 transaction:transaction];
    return message;
}

- (void)acceptNewIdentityKey
{
    [[TSStorageManager sharedManager] saveRemoteIdentity:self.newIdentityKey recipientId:self.recipientId];

    __block TSOutgoingMessage *_Nullable message;
    __block TSThread *thread;
    __block SignalRecipient *recipient;

    [[TSStorageManager sharedManager].newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            thread = [TSContactThread fetchObjectWithUniqueID:self.uniqueThreadId transaction:transaction];
            message = [TSOutgoingMessage fetchObjectWithUniqueID:self.messageId transaction:transaction];
            recipient = [SignalRecipient fetchObjectWithUniqueID:self.recipientId transaction:transaction];

            [self removeWithTransaction:transaction];
        }];


    if (message) {

        void (^logSuccess)() = ^void() {
            DDLogInfo(@"Successfully redelivered message to recipient after accepting new key.");
        };

        void (^logFailure)() = ^void() {
            DDLogWarn(@"Failed to redeliver message to recipient after accepting new key.");
        };
        // Resend to single recipient
        [[TSMessagesManager sharedManager] resendMessage:message
                                             toRecipient:recipient
                                                inThread:thread
                                                 success:logSuccess
                                                 failure:logFailure];
    }
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
