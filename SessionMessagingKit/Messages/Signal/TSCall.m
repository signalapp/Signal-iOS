//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalCoreKit/NSDate+OWS.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import <SessionMessagingKit/TSCall.h>
#import <SessionMessagingKit/TSContactThread.h>

NS_ASSUME_NONNULL_BEGIN

NSString *NSStringFromCallType(RPRecentCallType callType)
{
    switch (callType) {
        case RPRecentCallTypeIncoming:
            return @"RPRecentCallTypeIncoming";
        case RPRecentCallTypeOutgoing:
            return @"RPRecentCallTypeOutgoing";
        case RPRecentCallTypeIncomingMissed:
            return @"RPRecentCallTypeIncomingMissed";
        case RPRecentCallTypeOutgoingIncomplete:
            return @"RPRecentCallTypeOutgoingIncomplete";
        case RPRecentCallTypeIncomingIncomplete:
            return @"RPRecentCallTypeIncomingIncomplete";
        case RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity:
            return @"RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity";
        case RPRecentCallTypeIncomingDeclined:
            return @"RPRecentCallTypeIncomingDeclined";
        case RPRecentCallTypeOutgoingMissed:
            return @"RPRecentCallTypeOutgoingMissed";
        case RPRecentCallTypeIncomingAnsweredElsewhere:
            return @"RPRecentCallTypeIncomingAnsweredElsewhere";
        case RPRecentCallTypeIncomingDeclinedElsewhere:
            return @"RPRecentCallTypeIncomingDeclinedElsewhere";
        case RPRecentCallTypeIncomingBusyElsewhere:
            return @"RPRecentCallTypeIncomingBusyElsewhere";
    }
}

NSUInteger TSCallCurrentSchemaVersion = 1;

@interface TSCall ()

@property (nonatomic, getter=wasRead) BOOL read;

@property (nonatomic, readonly) NSUInteger callSchemaVersion;

@property (nonatomic) RPRecentCallType callType;
@property (nonatomic) TSRecentCallOfferType offerType;

@end

#pragma mark -

@implementation TSCall

- (instancetype)initWithCallType:(RPRecentCallType)callType
                       offerType:(TSRecentCallOfferType)offerType
                          thread:(TSContactThread *)thread
                 sentAtTimestamp:(uint64_t)sentAtTimestamp
{
    self = [super initInteractionWithTimestamp:sentAtTimestamp inThread:thread];

    if (!self) {
        return self;
    }

    _callSchemaVersion = TSCallCurrentSchemaVersion;
    _callType = callType;
    _offerType = offerType;

    // Ensure users are notified of missed calls.
    BOOL isIncomingMissed = (_callType == RPRecentCallTypeIncomingMissed
        || _callType == RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity);
    if (isIncomingMissed) {
        _read = NO;
    } else {
        _read = YES;
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (self.callSchemaVersion < 1) {
        // Assume user has already seen any call that predate read-tracking
        _read = YES;
    }

    _callSchemaVersion = TSCallCurrentSchemaVersion;

    return self;
}

- (OWSInteractionType)interactionType
{
    return OWSInteractionType_Call;
}

- (NSString *)previewTextWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    TSThread *thread = [self threadWithTransaction:transaction];
    TSContactThread *contactThread = (TSContactThread *)thread;
    NSString *sessionID = contactThread.contactSessionID;
    NSString *shortName = [[LKStorage.shared getContactWithSessionID:sessionID] displayNameFor:SNContactContextRegular] ?: sessionID;

    // We don't actually use the `transaction` but other sibling classes do.
    switch (_callType) {
        case RPRecentCallTypeIncoming:
        case RPRecentCallTypeIncomingIncomplete:
        case RPRecentCallTypeIncomingAnsweredElsewhere: {
            NSString *format = NSLocalizedString(
                @"INCOMING_CALL_FORMAT", @"info message text in conversation view. {embeds callee name}");
            return [NSString stringWithFormat:format, shortName];
        }
        case RPRecentCallTypeOutgoing:
        case RPRecentCallTypeOutgoingIncomplete:
        case RPRecentCallTypeOutgoingMissed: {
            NSString *format = NSLocalizedString(
                @"OUTGOING_CALL_FORMAT", @"info message text in conversation view. {embeds callee name}");
            return [NSString stringWithFormat:format, shortName];
        }
        case RPRecentCallTypeIncomingMissed:
        case RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity:
        case RPRecentCallTypeIncomingBusyElsewhere:
        case RPRecentCallTypeIncomingDeclined:
        case RPRecentCallTypeIncomingDeclinedElsewhere:
            return NSLocalizedString(@"MISSED_CALL", @"info message text in conversation view");
    }
}

#pragma mark - OWSReadTracking

- (uint64_t)expireStartedAt { return 0; }

- (BOOL)shouldAffectUnreadCounts { return YES; }

- (void)markAsReadAtTimestamp:(uint64_t)readTimestamp sendReadReceipt:(BOOL)sendReadReceipt transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (self.read) { return; }
    self.read = YES;
    [self saveWithTransaction:transaction];
}

#pragma mark - Methods

- (void)updateCallType:(RPRecentCallType)callType
{
    [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self updateCallType:callType transaction:transaction];
    }];
}

- (void)updateCallType:(RPRecentCallType)callType transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    self.callType = callType;
    [self saveWithTransaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
