//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyReceivingErrorMessage.h"
#import "OWSFingerprint.h"
#import "OWSIdentityManager.h"
#import "OWSMessageManager.h"
#import "OWSMessageReceiver.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
#import "TSErrorMessage_privateConstructor.h"
#import "TSStorageManager.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <AxolotlKit/PreKeyWhisperMessage.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

/// TODO we can eventually deprecate this, since incoming messages are now always decrypted.
@interface TSInvalidIdentityKeyReceivingErrorMessage ()

@property (nonatomic, readonly, copy) NSString *authorId;

@end

@implementation TSInvalidIdentityKeyReceivingErrorMessage {
    // Not using a property declaration in order to exclude from DB serialization
    OWSSignalServiceProtosEnvelope *_envelope;
}

@synthesize envelopeData = _envelopeData;

+ (instancetype)untrustedKeyWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                         withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    TSContactThread *contactThread =
        [TSContactThread getOrCreateThreadWithContactId:envelope.source transaction:transaction];
    TSInvalidIdentityKeyReceivingErrorMessage *errorMessage =
        [[self alloc] initForUnknownIdentityKeyWithTimestamp:envelope.timestamp
                                                    inThread:contactThread
                                            incomingEnvelope:envelope];
    return errorMessage;
}

- (instancetype)initForUnknownIdentityKeyWithTimestamp:(uint64_t)timestamp
                                              inThread:(TSThread *)thread
                                      incomingEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    self = [self initWithTimestamp:timestamp inThread:thread failedMessageType:TSErrorMessageWrongTrustedIdentityKey];
    if (!self) {
        return self;
    }

    _envelopeData = envelope.data;
    _authorId = envelope.source;

    return self;
}

- (OWSSignalServiceProtosEnvelope *)envelope
{
    if (!_envelope) {
        _envelope = [OWSSignalServiceProtosEnvelope parseFromData:self.envelopeData];
    }
    return _envelope;
}

- (void)acceptNewIdentityKey
{
    if (self.errorType != TSErrorMessageWrongTrustedIdentityKey) {
        DDLogError(@"Refusing to accept identity key for anything but a Key error.");
        return;
    }

    NSData *_Nullable newKey = [self newIdentityKey];
    if (!newKey) {
        OWSFail(@"Couldn't extract identity key to accept");
        return;
    }

    // Saving a new identity mutates the session store so it must happen on the sessionStoreQueue
    dispatch_async([OWSDispatch sessionStoreQueue], ^{
        [[OWSIdentityManager sharedManager] saveRemoteIdentity:newKey
                                                   recipientId:self.envelope.source
                                               protocolContext:protocolContext];

        dispatch_async(dispatch_get_main_queue(), ^{
            // Decrypt this and any old messages for the newly accepted key
            NSArray<TSInvalidIdentityKeyReceivingErrorMessage *> *messagesToDecrypt =
                [self.thread receivedMessagesForInvalidKey:newKey];

            for (TSInvalidIdentityKeyReceivingErrorMessage *errorMessage in messagesToDecrypt) {
                [[OWSMessageReceiver sharedInstance] handleReceivedEnvelope:errorMessage.envelope];

                // Here we remove the existing error message because handleReceivedEnvelope will either
                //  1.) succeed and create a new successful message in the thread or...
                //  2.) fail and create a new identical error message in the thread.
                [errorMessage remove];
            }
        });
    });
}

- (nullable NSData *)newIdentityKey
{
    if (!self.envelope) {
        DDLogError(@"Error message had no envelope data to extract key from");
        return nil;
    }

    if (self.envelope.type != OWSSignalServiceProtosEnvelopeTypePrekeyBundle) {
        DDLogError(@"Refusing to attempt key extraction from an envelope which isn't a prekey bundle");
        return nil;
    }

    // DEPRECATED - Remove after all clients have been upgraded.
    NSData *pkwmData = self.envelope.hasContent ? self.envelope.content : self.envelope.legacyMessage;
    if (!pkwmData) {
        DDLogError(@"Ignoring acceptNewIdentityKey for empty message");
        return nil;
    }

    PreKeyWhisperMessage *message = [[PreKeyWhisperMessage alloc] initWithData:pkwmData];
    return [message.identityKey removeKeyType];
}

- (NSString *)theirSignalId
{
    if (self.authorId) {
        return self.authorId;
    } else {
        // for existing messages before we were storing author id.
        return self.envelope.source;
    }
}

@end

NS_ASSUME_NONNULL_END
