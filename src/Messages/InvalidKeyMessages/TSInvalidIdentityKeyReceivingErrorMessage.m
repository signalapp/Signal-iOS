//  Created by Frederic Jacobs on 31/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSInvalidIdentityKeyReceivingErrorMessage.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
#import "TSErrorMessage_privateConstructor.h"
#import "TSFingerprintGenerator.h"
#import "TSMessagesManager.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "TSStorageManager.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <AxolotlKit/PreKeyWhisperMessage.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <YapDatabase/YapDatabaseView.h>

@implementation TSInvalidIdentityKeyReceivingErrorMessage

- (instancetype)initForUnknownIdentityKeyWithTimestamp:(uint64_t)timestamp
                                              inThread:(TSThread *)thread
                                    incomingPushSignal:(NSData *)signal {
    self = [self initWithTimestamp:timestamp inThread:thread failedMessageType:TSErrorMessageWrongTrustedIdentityKey];

    if (self) {
        self.pushSignal = signal;
    }

    return self;
}

+ (instancetype)untrustedKeyWithSignal:(IncomingPushMessageSignal *)preKeyMessage
                       withTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    TSContactThread *contactThread =
        [TSContactThread getOrCreateThreadWithContactId:preKeyMessage.source transaction:transaction];
    TSInvalidIdentityKeyReceivingErrorMessage *errorMessage =
        [[self alloc] initForUnknownIdentityKeyWithTimestamp:preKeyMessage.timestamp
                                                    inThread:contactThread
                                          incomingPushSignal:preKeyMessage.data];
    return errorMessage;
}

- (void)acceptNewIdentityKey {
    if (self.errorType != TSErrorMessageWrongTrustedIdentityKey || !self.pushSignal) {
        return;
    }

    TSStorageManager *storage         = [TSStorageManager sharedManager];
    IncomingPushMessageSignal *signal = [IncomingPushMessageSignal parseFromData:self.pushSignal];
    PreKeyWhisperMessage *message     = [[PreKeyWhisperMessage alloc] initWithData:signal.message];
    NSData *newKey                    = [message.identityKey removeKeyType];

    [storage saveRemoteIdentity:newKey recipientId:signal.source];

    [[TSMessagesManager sharedManager] handleMessageSignal:signal];

    __block NSMutableSet *messagesToDecrypt = [NSMutableSet set];

    [[TSStorageManager sharedManager]
            .dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      [[transaction ext:TSMessageDatabaseViewExtensionName]
          enumerateKeysAndObjectsInGroup:self.uniqueThreadId
                             withOptions:NSEnumerationReverse
                              usingBlock:^(
                                  NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                                TSInteraction *interaction = (TSInteraction *)object;

                                DDLogVerbose(@"Interaction type: %@", interaction.debugDescription);

                                if ([interaction isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
                                    TSInvalidIdentityKeyErrorMessage *invalidKeyMessage =
                                        (TSInvalidIdentityKeyReceivingErrorMessage *)interaction;
                                    IncomingPushMessageSignal *invalidMessageSignal =
                                        [IncomingPushMessageSignal parseFromData:invalidKeyMessage.pushSignal];
                                    PreKeyWhisperMessage *pkwm =
                                        [[PreKeyWhisperMessage alloc] initWithData:invalidMessageSignal.message];
                                    NSData *newKeyCandidate = [pkwm.identityKey removeKeyType];

                                    if ([newKeyCandidate isEqualToData:newKey]) {
                                        [messagesToDecrypt addObject:invalidKeyMessage];
                                    }
                                }
                              }];
    }];


    for (TSInvalidIdentityKeyReceivingErrorMessage *errorMessage in messagesToDecrypt) {
        [[TSMessagesManager sharedManager]
            handleMessageSignal:[IncomingPushMessageSignal parseFromData:errorMessage.pushSignal]];

        [[TSStorageManager sharedManager]
                .dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
          [errorMessage removeWithTransaction:transaction];
        }];
    }
}

- (NSString *)newIdentityKey {
    if (!self.pushSignal) {
        return @"";
    }

    IncomingPushMessageSignal *signal = [IncomingPushMessageSignal parseFromData:self.pushSignal];
    PreKeyWhisperMessage *message     = [[PreKeyWhisperMessage alloc] initWithData:signal.message];
    NSData *identityKey               = [message.identityKey removeKeyType];

    return [TSFingerprintGenerator getFingerprintForDisplay:identityKey];
}

@end
