//
//  TSErrorMessage.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "IncomingPushMessageSignal.pb.h"
#import "TSMessage.h"

@interface TSErrorMessage : TSMessage

typedef NS_ENUM(int32_t, TSErrorMessageType) {
    TSErrorMessageNoSession,
    TSErrorMessageWrongTrustedIdentityKey,
    TSErrorMessageInvalidKeyException,
    TSErrorMessageMissingKeyId,
    TSErrorMessageInvalidMessage,
    TSErrorMessageDuplicateMessage,
    TSErrorMessageInvalidVersion,
};

+ (instancetype)corruptedMessageWithSignal:(IncomingPushMessageSignal *)preKeyMessage
                           withTransaction:(YapDatabaseReadWriteTransaction *)transaction;
+ (instancetype)invalidVersionWithSignal:(IncomingPushMessageSignal *)preKeyMessage
                         withTransaction:(YapDatabaseReadWriteTransaction *)transaction;
+ (instancetype)missingKeyIdWithSignal:(IncomingPushMessageSignal *)preKeyMessage
                       withTransaction:(YapDatabaseReadWriteTransaction *)transaction;
+ (instancetype)invalidKeyExceptionWithSignal:(IncomingPushMessageSignal *)preKeyMessage
                              withTransaction:(YapDatabaseReadWriteTransaction *)transaction;
+ (instancetype)missingSessionWithSignal:(IncomingPushMessageSignal *)preKeyMessage
                         withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

@property (nonatomic, readonly) TSErrorMessageType errorType;

@end
