//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSCall.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import <JSQMessagesViewController/JSQMessagesTimestampFormatter.h>
#import <JSQMessagesViewController/UIImage+JSQMessages.h>
#import <SignalServiceKit/TSCall.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSCall ()

// -- Redeclaring properties from OWSMessageData protocol to synthesize variables
@property (nonatomic) TSMessageAdapterType messageType;
@property (nonatomic) BOOL isExpiringMessage;
@property (nonatomic) BOOL shouldStartExpireTimer;
@property (nonatomic) uint64_t expiresAtSeconds;
@property (nonatomic) uint32_t expiresInSeconds;
@property (nonatomic) TSInteraction *interaction;

@end

@implementation OWSCall

#pragma mark - Initialzation

- (instancetype)initWithCallRecord:(TSCall *)callRecord
{
    TSThread *thread = callRecord.thread;
    TSContactThread *contactThread;
    if ([thread isKindOfClass:[TSContactThread class]]) {
        contactThread = (TSContactThread *)thread;
    } else {
        DDLogError(@"%@ Unexpected thread type: %@", self.tag, thread);
    }

    CallStatus status = 0;
    switch (callRecord.callType) {
        case RPRecentCallTypeOutgoing:
            status = kCallOutgoing;
            break;
        case RPRecentCallTypeOutgoingIncomplete:
            status = kCallOutgoingIncomplete;
            break;
        case RPRecentCallTypeMissed:
            status = kCallMissed;
            break;
        case RPRecentCallTypeIncoming:
            status = kCallIncoming;
            break;
        case RPRecentCallTypeIncomingIncomplete:
            status = kCallIncomingIncomplete;
            break;
        default:
            status = kCallIncoming;
            break;
    }

    NSString *name = contactThread.name;
    NSString *detailString;
    switch (status) {
        case kCallMissed:
            detailString = [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_MISSED_CALL_WITH_NAME", nil), name];
            break;
        case kCallIncoming:
            detailString = [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_RECEIVED_CALL", nil), name];
            break;
        case kCallIncomingIncomplete:
            detailString = [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_THEY_TRIED_TO_CALL_YOU", nil), name];
            break;
        case kCallOutgoing:
            detailString = [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_YOU_CALLED", nil), name];
            break;
        case kCallOutgoingIncomplete:
            detailString = [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_YOU_TRIED_TO_CALL", nil), name];
            break;
        default:
            detailString = @"";
            break;
    }

    return [self initWithInteraction:callRecord
                            callerId:contactThread.contactIdentifier
                   callerDisplayName:name
                                date:callRecord.date
                              status:status
                       displayString:detailString];
}

- (instancetype)initWithInteraction:(TSInteraction *)interaction
                           callerId:(NSString *)senderId
                  callerDisplayName:(NSString *)senderDisplayName
                               date:(nullable NSDate *)date
                             status:(CallStatus)status
                      displayString:(NSString *)detailString
{
    NSParameterAssert(senderId != nil);
    NSParameterAssert(senderDisplayName != nil);

    self = [super init];
    if (!self) {
        return self;
    }

    _interaction = interaction;
    _senderId = [senderId copy];
    _senderDisplayName = [senderDisplayName copy];
    _date = [date copy];
    _status = status;
    _isExpiringMessage = NO; // TODO - call notifications should expire too.
    _shouldStartExpireTimer = NO; // TODO - call notifications should expire too.
    _messageType = TSCallAdapter;

    // TODO interpret detailString from status. make sure it works for calls and
    // our re-use of calls as group update display
    _detailString = [detailString stringByAppendingFormat:@" "];

    return self;
}

- (NSString *)dateText
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.timeStyle = NSDateFormatterShortStyle;
    dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    dateFormatter.doesRelativeDateFormatting = YES;
    return [dateFormatter stringFromDate:_date];
}

#pragma mark - NSObject

- (BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[self class]]) {
        return NO;
    }

    OWSCall *aCall = (OWSCall *)object;

    return [self.senderId isEqualToString:aCall.senderId] &&
        [self.senderDisplayName isEqualToString:aCall.senderDisplayName]
        && ([self.date compare:aCall.date] == NSOrderedSame) && self.status == aCall.status;
}

- (NSUInteger)hash
{
    return self.senderId.hash ^ self.date.hash;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: senderId=%@, senderDisplayName=%@, date=%@>",
                     [self class],
                     self.senderId,
                     self.senderDisplayName,
                     self.date];
}

#pragma mark - OWSMessageEditing

- (BOOL)canPerformEditingAction:(SEL)action
{
    return action == @selector(delete:);
}

- (void)performEditingAction:(SEL)action
{
    // Deletes are always handled by TSMessageAdapter
    if (action == @selector(delete:)) {
        DDLogDebug(@"%@ Deleting interaction with uniqueId: %@", self.tag, self.interaction.uniqueId);
        [self.interaction remove];
        return;
    }

    // Shouldn't get here, as only supported actions should be exposed via canPerformEditingAction
    NSString *actionString = NSStringFromSelector(action);
    DDLogError(@"%@ '%@' action unsupported", self.tag, actionString);
}

#pragma mark - JSQMessageData

- (BOOL)isMediaMessage
{
    return NO;
}

- (NSUInteger)messageHash
{
    return self.hash;
}

- (NSString *)text
{
    return _detailString;
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
