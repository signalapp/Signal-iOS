//
//  TSInvalidIdentityKeySendingErrorMessage.m
//  Signal
//
//  Created by Frederic Jacobs on 15/02/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

#import <AxolotlKit/NSData+keyVersionByte.h>

#import "PreKeyBundle+jsonDict.h"
#import "TSContactThread.h"
#import "TSErrorMessage_privateConstructor.h"
#import "TSFingerprintGenerator.h"
#import "TSInvalidIdentityKeySendingErrorMessage.h"
#import "TSMessagesManager+sendMessages.h"
#import "TSStorageManager+IdentityKeyStore.h"

@interface TSInvalidIdentityKeySendingErrorMessage ()

@property (nonatomic, readonly) PreKeyBundle *preKeyBundle;
@property (nonatomic, readonly) NSString *recipientId;
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
    [[TSStorageManager sharedManager] saveRemoteIdentity:[self newKey] recipientId:self.recipientId];

    __block TSOutgoingMessage *message;
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

- (NSString *)newIdentityKey {
    NSData *identityKey = [self newKey];

    return [TSFingerprintGenerator getFingerprintForDisplay:identityKey];
}

- (NSData *)newKey {
    return [self.preKeyBundle.identityKey removeKeyType];
}

@end
