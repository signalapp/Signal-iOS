//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSInfoMessage.h"
#import "NSDate+millisecondTimeStamp.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

NSUInteger TSInfoMessageSchemaVersion = 1;

@interface TSInfoMessage ()

@property (nonatomic, getter=wasRead) BOOL read;

@property (nonatomic, readonly) NSUInteger infoMessageSchemaVersion;

@end

#pragma mark -

@implementation TSInfoMessage

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (self.infoMessageSchemaVersion < 1) {
        _read = YES;
    }

    _infoMessageSchemaVersion = TSInfoMessageSchemaVersion;

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageType:(TSInfoMessageType)infoMessage
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

    _messageType = infoMessage;
    _infoMessageSchemaVersion = TSInfoMessageSchemaVersion;

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageType:(TSInfoMessageType)infoMessage
                    customMessage:(NSString *)customMessage {
    self = [self initWithTimestamp:timestamp inThread:thread messageType:infoMessage];
    if (self) {
        _customMessage = customMessage;
    }
    return self;
}

+ (instancetype)userNotRegisteredMessageInThread:(TSThread *)thread
{
    return [[self alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                  inThread:thread
                               messageType:TSInfoMessageUserNotRegistered];
}

- (NSString *)description {
    switch (_messageType) {
        case TSInfoMessageTypeSessionDidEnd:
            return NSLocalizedString(@"SECURE_SESSION_RESET", nil);
        case TSInfoMessageTypeUnsupportedMessage:
            return NSLocalizedString(@"UNSUPPORTED_ATTACHMENT", nil);
        case TSInfoMessageUserNotRegistered:
            return NSLocalizedString(@"CONTACT_DETAIL_COMM_TYPE_INSECURE", nil);
        case TSInfoMessageTypeGroupQuit:
            return NSLocalizedString(@"GROUP_YOU_LEFT", nil);
        case TSInfoMessageTypeGroupUpdate:
            return _customMessage != nil ? _customMessage : NSLocalizedString(@"GROUP_UPDATED", nil);
        case TSInfoMessageAddToContactsOffer:
            return NSLocalizedString(@"ADD_TO_CONTACTS_OFFER",
                @"Message shown in conversation view that offers to add an unknown user to your phone's contacts.");
        case TSInfoMessageVerificationStateChange:
            return NSLocalizedString(@"VERIFICATION_STATE_CHANGE_GENERIC",
                @"Generic message indicating that verification state changed for a given user.");
        case TSInfoMessageAddUserToProfileWhitelistOffer:
            return NSLocalizedString(@"ADD_USER_TO_PROFILE_WHITELIST_OFFER",
                @"Message shown in conversation view that offers to share your profile with a user.");
        case TSInfoMessageAddGroupToProfileWhitelistOffer:
            return NSLocalizedString(@"ADD_GROUP_TO_PROFILE_WHITELIST_OFFER",
                @"Message shown in conversation view that offers to share your profile with a group.");
        default:
            break;
    }

    return @"Unknown Info Message Type";
}

#pragma mark - OWSReadTracking

- (BOOL)shouldAffectUnreadCounts
{
    return NO;
}

- (void)markAsReadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
                  sendReadReceipt:(BOOL)sendReadReceipt
                 updateExpiration:(BOOL)updateExpiration
{
    OWSAssert(transaction);

    if (_read) {
        return;
    }

    DDLogDebug(@"%@ marking as read uniqueId: %@ which has timestamp: %llu", self.tag, self.uniqueId, self.timestamp);
    _read = YES;
    [self saveWithTransaction:transaction];
    [self touchThreadWithTransaction:transaction];

    // Ignore sendReadReceipt and updateExpiration; they don't apply to info messages.
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
