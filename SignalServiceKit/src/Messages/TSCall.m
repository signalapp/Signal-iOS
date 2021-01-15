//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "TSCall.h"
#import "TSContactThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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
    self = [super initInteractionWithTimestamp:sentAtTimestamp thread:thread];

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

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          sortId:(uint64_t)sortId
                       timestamp:(uint64_t)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                        callType:(RPRecentCallType)callType
                       offerType:(TSRecentCallOfferType)offerType
                            read:(BOOL)read
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId
               receivedAtTimestamp:receivedAtTimestamp
                            sortId:sortId
                         timestamp:timestamp
                    uniqueThreadId:uniqueThreadId];

    if (!self) {
        return self;
    }

    _callType = callType;
    _offerType = offerType;
    _read = read;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

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

- (NSString *)previewTextWithTransaction:(SDSAnyReadTransaction *)transaction
{
    TSThread *thread = [self threadWithTransaction:transaction];
    OWSAssertDebug([thread isKindOfClass:[TSContactThread class]]);
    TSContactThread *contactThread = (TSContactThread *)thread;
    NSString *shortName = [SSKEnvironment.shared.contactsManager shortDisplayNameForAddress:contactThread.contactAddress
                                                                                transaction:transaction];

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

- (uint64_t)expireStartedAt
{
    return 0;
}

- (BOOL)shouldAffectUnreadCounts
{
    return YES;
}

- (void)markAsReadAtTimestamp:(uint64_t)readTimestamp
                       thread:(TSThread *)thread
                 circumstance:(OWSReadCircumstance)circumstance
                  transaction:(SDSAnyWriteTransaction *)transaction
{

    OWSAssertDebug(transaction);

    if (self.read) {
        return;
    }

    OWSLogDebug(@"marking as read uniqueId: %@ which has timestamp: %llu", self.uniqueId, self.timestamp);

    [self anyUpdateCallWithTransaction:transaction
                                 block:^(TSCall *call) {
                                     call.read = YES;
                                 }];

    // Ignore `circumstance` - we never send read receipts for calls.
}

#pragma mark - Methods

- (void)updateCallType:(RPRecentCallType)callType
{
    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self updateCallType:callType transaction:transaction];
    });
}

- (void)updateCallType:(RPRecentCallType)callType transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    OWSLogInfo(@"updating call type of call: %@ -> %@ with uniqueId: %@ which has timestamp: %llu",
        NSStringFromCallType(_callType),
        NSStringFromCallType(callType),
        self.uniqueId,
        self.timestamp);

    [self anyUpdateCallWithTransaction:transaction
                                 block:^(TSCall *call) {
                                     call.callType = callType;
                                 }];
}

@end

NS_ASSUME_NONNULL_END
