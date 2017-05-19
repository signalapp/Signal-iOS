//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"
#import "ContactsManagerProtocol.h"
#import "NSDate+millisecondTimeStamp.h"
#import "NotificationsProtocol.h"
#import "TSContactThread.h"
#import "TSErrorMessage_privateConstructor.h"
#import "TSMessagesManager.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSErrorMessage

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType
{
    return [self initWithTimestamp:timestamp inThread:thread failedMessageType:errorMessageType recipientId:nil];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType
                      recipientId:(nullable NSString *)recipientId
{
    self = [super initWithTimestamp:timestamp
                           inThread:thread
                        messageBody:nil
                      attachmentIds:@[]
                   expiresInSeconds:0
                    expireStartedAt:0];

    if (!self) {
        return self;
    }

    _errorType = errorMessageType;
    _recipientId = recipientId;

    // TODO: Move this out of model class.
    //
    //       For now, dispatch async to ensure we're not inside a transaction
    //       and thereby avoid deadlock.
    TSErrorMessage *errorMessage = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[TextSecureKitEnv sharedEnv].notificationsManager notifyUserForErrorMessage:errorMessage inThread:thread];
    });

    return self;
}

- (instancetype)initWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                 withTransaction:(YapDatabaseReadWriteTransaction *)transaction
               failedMessageType:(TSErrorMessageType)errorMessageType
{
    TSContactThread *contactThread =
        [TSContactThread getOrCreateThreadWithContactId:envelope.source transaction:transaction];

    return [self initWithTimestamp:envelope.timestamp inThread:contactThread failedMessageType:errorMessageType];
}

- (NSString *)description {
    switch (_errorType) {
        case TSErrorMessageNoSession:
            return NSLocalizedString(@"ERROR_MESSAGE_NO_SESSION", @"");
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
        case TSErrorMessageNonBlockingIdentityChange: {
            if (self.recipientId) {
                NSString *messageFormat = NSLocalizedString(@"ERROR_MESSAGE_NON_BLOCKING_IDENTITY_CHANGE_FORMAT",
                    @"Shown when signal users safety numbers changed, embeds the user's {{name or phone number}}");

                NSString *recipientDisplayName =
                    [[TextSecureKitEnv sharedEnv].contactsManager displayNameForPhoneIdentifier:self.recipientId];
                return [NSString stringWithFormat:messageFormat, recipientDisplayName];
            } else {
                // recipientId will be nil for legacy errors
                return NSLocalizedString(
                    @"ERROR_MESSAGE_NON_BLOCKING_IDENTITY_CHANGE", @"Shown when signal users safety numbers changed");
            }
            break;
        }
        case TSErrorMessageUnknownContactBlockOffer:
            return NSLocalizedString(@"UNKNOWN_CONTACT_BLOCK_OFFER",
                @"Message shown in conversation view that offers to block an unknown user.");
        default:
            return NSLocalizedString(@"ERROR_MESSAGE_UNKNOWN_ERROR", @"");
            break;
    }
}

+ (instancetype)corruptedMessageWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                             withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    return [[self alloc] initWithEnvelope:envelope
                          withTransaction:transaction
                        failedMessageType:TSErrorMessageInvalidMessage];
}

+ (instancetype)invalidVersionWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                           withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    return [[self alloc] initWithEnvelope:envelope
                          withTransaction:transaction
                        failedMessageType:TSErrorMessageInvalidVersion];
}

+ (instancetype)invalidKeyExceptionWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                                withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    return [[self alloc] initWithEnvelope:envelope
                          withTransaction:transaction
                        failedMessageType:TSErrorMessageInvalidKeyException];
}

+ (instancetype)missingSessionWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                           withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    return
        [[self alloc] initWithEnvelope:envelope withTransaction:transaction failedMessageType:TSErrorMessageNoSession];
}

+ (instancetype)nonblockingIdentityChangeInThread:(TSThread *)thread recipientId:(NSString *)recipientId
{
    return [[self alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                  inThread:thread
                         failedMessageType:TSErrorMessageNonBlockingIdentityChange
                               recipientId:recipientId];
}

@end

NS_ASSUME_NONNULL_END
