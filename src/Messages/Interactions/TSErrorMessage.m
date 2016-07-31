//
//  TSErrorMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"
#import "TSContactThread.h"
#import "TSErrorMessage_privateConstructor.h"
#import "TSMessagesManager.h"
#import "TextSecureKitEnv.h"

@implementation TSErrorMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType
{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:nil attachmentIds:nil];

    if (!self) {
        return self;
    }

    _errorType = errorMessageType;

    [[TextSecureKitEnv sharedEnv].notificationsManager notifyUserForErrorMessage:self inThread:thread];

    return self;
}

- (instancetype)initWithSignal:(IncomingPushMessageSignal *)signal
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
             failedMessageType:(TSErrorMessageType)errorMessageType {
    TSContactThread *contactThread =
        [TSContactThread getOrCreateThreadWithContactId:signal.source transaction:transaction];

    return [self initWithTimestamp:signal.timestamp inThread:contactThread failedMessageType:errorMessageType];
}

- (NSString *)description {
    switch (_errorType) {
        case TSErrorMessageNoSession:
            return NSLocalizedString(@"ERROR_MESSAGE_NO_SESSION", @"");
        case TSErrorMessageMissingKeyId:
            return NSLocalizedString(@"ERROR_MESSAGE_MISSING_KEY", @"");
        case TSErrorMessageInvalidMessage:
            return NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @"");
        case TSErrorMessageInvalidVersion:
            return NSLocalizedString(@"ERROR_MESSAGE_INVALID_VERSION", @"");
        case TSErrorMessageDuplicateMessage:
            return NSLocalizedString(@"ERROR_MESSAGE_DUPLICATE_MESSAGE", @"");
        case TSErrorMessageInvalidKeyException:
            return NSLocalizedString(@"ERROR_MESSAGE_INVALID_KEY_EXCEPTION", @"");
        case TSErrorMessageWrongTrustedIdentityKey:
            return NSLocalizedString(@"ERROR_MESSAGE_WRONG_TRUSTED_IDENTITY_KEY", @"");
        default:
            return NSLocalizedString(@"ERROR_MESSAGE_UNKNOWN_ERROR", @"");
            break;
    }
}

+ (instancetype)corruptedMessageWithSignal:(IncomingPushMessageSignal *)signal
                           withTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageInvalidMessage];
}

+ (instancetype)invalidVersionWithSignal:(IncomingPushMessageSignal *)signal
                         withTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageInvalidVersion];
}

+ (instancetype)missingKeyIdWithSignal:(IncomingPushMessageSignal *)signal
                       withTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageMissingKeyId];
}

+ (instancetype)invalidKeyExceptionWithSignal:(IncomingPushMessageSignal *)signal
                              withTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    return [[self alloc] initWithSignal:signal
                            transaction:transaction
                      failedMessageType:TSErrorMessageInvalidKeyException];
}

+ (instancetype)missingSessionWithSignal:(IncomingPushMessageSignal *)signal
                         withTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageNoSession];
}

@end
