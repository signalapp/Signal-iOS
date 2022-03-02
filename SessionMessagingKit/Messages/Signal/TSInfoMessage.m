//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSInfoMessage.h"
#import "TSContactThread.h"
#import "SSKEnvironment.h"
#import <YapDatabase/YapDatabaseConnection.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>

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

    if (self.isDynamicInteraction) {
        self.read = YES;
    }

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageType:(TSInfoMessageType)infoMessage
{
    // MJK TODO - remove senderTimestamp
    self = [super initMessageWithTimestamp:timestamp
                                  inThread:thread
                               messageBody:nil
                             attachmentIds:@[]
                          expiresInSeconds:0
                           expireStartedAt:0
                             quotedMessage:nil
                               linkPreview:nil
                   openGroupInvitationName:nil
                    openGroupInvitationURL:nil
                                serverHash:nil];

    if (!self) {
        return self;
    }

    _messageType = infoMessage;
    _callState = TSInfoMessageCallStateUnknown;
    _infoMessageSchemaVersion = TSInfoMessageSchemaVersion;

    if (self.isDynamicInteraction) {
        self.read = YES;
    }

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageType:(TSInfoMessageType)infoMessage
                    customMessage:(NSString *)customMessage
{
    self = [self initWithTimestamp:timestamp inThread:thread messageType:infoMessage];
    if (self) {
        _customMessage = customMessage;
    }
    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageType:(TSInfoMessageType)infoMessage
          unregisteredRecipientId:(NSString *)unregisteredRecipientId
{
    self = [self initWithTimestamp:timestamp inThread:thread messageType:infoMessage];
    if (self) {
        _unregisteredRecipientId = unregisteredRecipientId;
    }
    return self;
}

- (OWSInteractionType)interactionType
{
    return OWSInteractionType_Info;
}

- (NSString *)getCallMessagePreviewTextWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    TSThread *thread = [self threadWithTransaction:transaction];
    if ([thread isKindOfClass: [TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        NSString *sessionID = contactThread.contactSessionID;
        NSString *name = [contactThread nameWithTransaction:transaction];
        if ([name isEqual:sessionID]) {
            name = [NSString stringWithFormat:@"%@...%@", [sessionID substringToIndex:4], [sessionID substringFromIndex:sessionID.length - 4]];
        }
        switch (_callState) {
            case TSInfoMessageCallStateIncoming:
                return [NSString stringWithFormat:NSLocalizedString(@"call_incoming", @""), name];
            case TSInfoMessageCallStateOutgoing:
                return [NSString stringWithFormat:NSLocalizedString(@"call_outgoing", @""), name];
            case TSInfoMessageCallStateMissed:
                return [NSString stringWithFormat:NSLocalizedString(@"call_missed", @""), name];
            default:
                break;
        }
    }
    return _customMessage;
}

- (NSString *)previewTextWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    
    switch (_messageType) {
        case TSInfoMessageTypeGroupCreated:
            return NSLocalizedString(@"GROUP_CREATED", @"");
        case TSInfoMessageTypeGroupCurrentUserLeft:
            return NSLocalizedString(@"GROUP_YOU_LEFT", @"");
        case TSInfoMessageTypeGroupUpdated:
            return _customMessage != nil ? _customMessage : NSLocalizedString(@"GROUP_UPDATED", @"");
        case TSInfoMessageTypeCall:
            return [self getCallMessagePreviewTextWithTransaction:transaction];
        case TSInfoMessageTypeMessageRequestAccepted:
            return NSLocalizedString(@"MESSAGE_REQUESTS_ACCEPTED", @"");
        default:
            break;
    }

    return @"Unknown Info Message Type";
}

#pragma mark - OWSReadTracking

- (BOOL)shouldAffectUnreadCounts
{
    switch (_messageType) {
        case TSInfoMessageTypeCall:
            return YES;
        default:
            return NO;
    }
}

- (uint64_t)expireStartedAt
{
    return 0;
}

- (void)markAsReadAtTimestamp:(uint64_t)readTimestamp
           trySendReadReceipt:(BOOL)trySendReadReceipt
                  transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (_read) {
        return;
    }

    _read = YES;
    [self saveWithTransaction:transaction];

    // Ignore trySendReadReceipt, it doesn't apply to info messages.
}

@end

NS_ASSUME_NONNULL_END
