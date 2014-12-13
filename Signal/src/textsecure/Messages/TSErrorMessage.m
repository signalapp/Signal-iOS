//
//  TSErrorMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"
#import "NSDate+millisecondTimeStamp.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import <AxolotlKit/PreKeyWhisperMessage.h>
#import <AxolotlKit/NSData+keyVersionByte.h>
#import "TSMessagesManager.h"
#import "TSFingerprintGenerator.h"

@interface TSErrorMessage()
@property NSData *pushSignal;
@end

@implementation TSErrorMessage

- (instancetype)initForUnknownIdentityKeyWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread incomingPushSignal:(NSData*)signal{
    self = [self initWithTimestamp:timestamp inThread:thread failedMessageType:TSErrorMessageWrongTrustedIdentityKey];
    
    if (self) {
        _pushSignal = signal;
    }
    
    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread failedMessageType:(TSErrorMessageType)errorMessageType{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:nil attachements:nil];
    
    if (self) {
        _errorType = errorMessageType;
    }
    
    return self;
}

- (instancetype)initWithSignal:(IncomingPushMessageSignal*)signal transaction:(YapDatabaseReadWriteTransaction*)transaction failedMessageType:(TSErrorMessageType)errorMessageType{
    TSContactThread *contactThread = [TSContactThread threadWithContactId:signal.source transaction:transaction];
    return [self initWithTimestamp:signal.timestamp inThread:contactThread failedMessageType:errorMessageType];
}

- (NSString*)description{
    switch (_errorType) {
        case TSErrorMessageNoSession:
            return @"No available session for contact";
        case TSErrorMessageMissingKeyId:
            return @"Received a message with unknown PreKey";
        case TSErrorMessageInvalidMessage:
            return @"Received a corrupted message";
        case TSErrorMessageInvalidVersion:
            return @"Received a message not compatible with this version";
        case TSErrorMessageDuplicateMessage:
            return @"Received a duplicated message";
        case TSErrorMessageInvalidKeyException:
            return @"The recipient's key is not valid.";
        case TSErrorMessageWrongTrustedIdentityKey:
            return @"Identity key changed. Tap to verify new key.";
        default:
            return @"An unknown error occured";
            break;
    }
}

+ (instancetype)corruptedMessageWithSignal:(IncomingPushMessageSignal *)signal withTransaction:(YapDatabaseReadWriteTransaction *)transaction{
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageInvalidMessage];
}

+ (instancetype)invalidVersionWithSignal:(IncomingPushMessageSignal*)signal withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageInvalidVersion];
}

+ (instancetype)missingKeyIdWithSignal:(IncomingPushMessageSignal*)signal withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageMissingKeyId];
}

+ (instancetype)invalidKeyExceptionWithSignal:(IncomingPushMessageSignal*)signal withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageInvalidKeyException];
}

+ (instancetype)untrustedKeyWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    TSContactThread *contactThread = [TSContactThread threadWithContactId:preKeyMessage.source transaction:transaction];
    TSErrorMessage *errorMessage = [[self alloc] initForUnknownIdentityKeyWithTimestamp:preKeyMessage.timestamp inThread:contactThread incomingPushSignal:preKeyMessage.data];
    return errorMessage;
}

+ (instancetype)missingSessionWithSignal:(IncomingPushMessageSignal*)signal withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageNoSession];
}

- (void)acceptNewIdentityKey{
    if (_errorType != TSErrorMessageWrongTrustedIdentityKey || !_pushSignal) {
        return;
    }
    
    TSStorageManager *storage = [TSStorageManager sharedManager];
    IncomingPushMessageSignal *signal = [IncomingPushMessageSignal parseFromData:_pushSignal];
    PreKeyWhisperMessage *message = [[PreKeyWhisperMessage alloc] initWithData:signal.message];
    NSData *newKey = [message.identityKey removeKeyType];
    
    [storage saveRemoteIdentity:newKey recipientId:signal.source];
    
    [[TSMessagesManager sharedManager] handleMessageSignal:signal];
    //TODO: Decrypt any other messages encrypted with that new identity key automatically.
}

- (NSString *)newIdentityKey{
    if (_errorType != TSErrorMessageWrongTrustedIdentityKey || !_pushSignal) {
        return @"";
    }
    
    IncomingPushMessageSignal *signal = [IncomingPushMessageSignal parseFromData:_pushSignal];
    PreKeyWhisperMessage *message     = [[PreKeyWhisperMessage alloc] initWithData:signal.message];
    NSData *identityKey               = [message.identityKey removeKeyType];
    
    return [TSFingerprintGenerator getFingerprintForDisplay:identityKey];
}

@end
