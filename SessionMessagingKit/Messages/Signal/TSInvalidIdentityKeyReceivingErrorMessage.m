//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyReceivingErrorMessage.h"
#import "OWSIdentityManager.h"
#import "OWSPrimaryStorage.h"
#import "SSKEnvironment.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
#import "TSErrorMessage_privateConstructor.h"
#import <SessionProtocolKit/NSData+keyVersionByte.h>
#import <SessionProtocolKit/PreKeyWhisperMessage.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

__attribute__((deprecated)) @interface TSInvalidIdentityKeyReceivingErrorMessage()

@property (nonatomic, readonly, copy) NSString *authorId;

@end

@implementation TSInvalidIdentityKeyReceivingErrorMessage {
    // Not using a property declaration in order to exclude from DB serialization
    SNProtoEnvelope *_Nullable _envelope;
}

@synthesize envelopeData = _envelopeData;

#ifdef DEBUG
// We no longer create these messages, but they might exist on legacy clients so it's useful to be able to
// create them with the debug UI
+ (nullable instancetype)untrustedKeyWithEnvelope:(SNProtoEnvelope *)envelope
                                  withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    TSContactThread *contactThread =
    [TSContactThread getOrCreateThreadWithContactId:envelope.source transaction:transaction];

    // Legit usage of senderTimestamp, references message which failed to decrypt
    TSInvalidIdentityKeyReceivingErrorMessage *errorMessage =
        [[self alloc] initForUnknownIdentityKeyWithTimestamp:envelope.timestamp
                                                    inThread:contactThread
                                            incomingEnvelope:envelope];
    return errorMessage;
}

- (nullable instancetype)initForUnknownIdentityKeyWithTimestamp:(uint64_t)timestamp
                                                       inThread:(TSThread *)thread
                                               incomingEnvelope:(SNProtoEnvelope *)envelope
{
    self = [self initWithTimestamp:timestamp inThread:thread failedMessageType:TSErrorMessageWrongTrustedIdentityKey];
    if (!self) {
        return self;
    }
    
    NSError *error;
    _envelopeData = [envelope serializedDataAndReturnError:&error];
    if (!_envelopeData || error != nil) {
        return nil;
    }
    
    _authorId = envelope.source;
    
    return self;
}
#endif

- (nullable SNProtoEnvelope *)envelope
{
    if (!_envelope) {
        NSError *error;
        SNProtoEnvelope *_Nullable envelope = [SNProtoEnvelope parseData:self.envelopeData error:&error];
        if (error || envelope == nil) {

        } else {
            _envelope = envelope;
        }
    }
    return _envelope;
}

- (void)throws_acceptNewIdentityKey
{
    if (self.errorType != TSErrorMessageWrongTrustedIdentityKey) {
        return;
    }

    NSData *_Nullable newKey = [self throws_newIdentityKey];
    if (!newKey) {
        return;
    }

    [[OWSIdentityManager sharedManager] saveRemoteIdentity:newKey recipientId:self.envelope.source];

    // Decrypt this and any old messages for the newly accepted key
    NSArray<TSInvalidIdentityKeyReceivingErrorMessage *> *messagesToDecrypt =
        [self.thread receivedMessagesForInvalidKey:newKey];

    for (TSInvalidIdentityKeyReceivingErrorMessage *errorMessage in messagesToDecrypt) {

        // Here we remove the existing error message because handleReceivedEnvelope will either
        //  1.) succeed and create a new successful message in the thread or...
        //  2.) fail and create a new identical error message in the thread.
        [errorMessage remove];
    }
}

- (nullable NSData *)throws_newIdentityKey
{
    if (!self.envelope) {
        return nil;
    }

    if (self.envelope.type != SNProtoEnvelopeTypePrekeyBundle) {
        return nil;
    }

    NSData *pkwmData = self.envelope.content;
    if (!pkwmData) {
        return nil;
    }

    PreKeyWhisperMessage *message = [[PreKeyWhisperMessage alloc] init_throws_withData:pkwmData];
    return [message.identityKey throws_removeKeyType];
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
