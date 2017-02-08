//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSCall.h"
#import "TSContactThread.h"
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

NSUInteger TSCallCurrentSchemaVersion = 1;

@interface TSCall ()

@property (nonatomic, readonly) NSUInteger callSchemaVersion;

@end

@implementation TSCall

@synthesize read = _read;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                   withCallNumber:(NSString *)contactNumber
                         callType:(RPRecentCallType)callType
                         inThread:(TSContactThread *)thread
{
    self = [super initWithTimestamp:timestamp inThread:thread];

    if (!self) {
        return self;
    }

    _callSchemaVersion = TSCallCurrentSchemaVersion;
    _callType = callType;
    if (_callType == RPRecentCallTypeMissed) {
        _read = NO;
    } else {
        _read = YES;
    }

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
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

- (NSString *)description {
    switch (_callType) {
        case RPRecentCallTypeIncoming:
            return NSLocalizedString(@"INCOMING_CALL", @"");
        case RPRecentCallTypeOutgoing:
            return NSLocalizedString(@"OUTGOING_CALL", @"");
        case RPRecentCallTypeMissed:
            return NSLocalizedString(@"MISSED_CALL", @"");
        case RPRecentCallTypeOutgoingIncomplete:
            return NSLocalizedString(@"OUTGOING_INCOMPLETE_CALL", @"");
        case RPRecentCallTypeIncomingIncomplete:
            return NSLocalizedString(@"INCOMING_INCOMPLETE_CALL", @"");
    }
}

#pragma mark - OWSReadTracking

- (void)markAsReadLocallyWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    DDLogInfo(@"%@ marking as read uniqueId: %@ which has timestamp: %llu", self.tag, self.uniqueId, self.timestamp);

    _read = YES;
    [self saveWithTransaction:transaction];

    // redraw any thread-related unread count UI.
    [self touchThreadWithTransaction:transaction];
}

- (void)markAsReadLocally
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self markAsReadLocallyWithTransaction:transaction];
    }];
}

#pragma mark - Methods

- (void)updateCallType:(RPRecentCallType)callType
{
    DDLogInfo(@"%@ updating call type of call: %d with uniqueId: %@ which has timestamp: %llu",
        self.tag,
        (int)self.callType,
        self.uniqueId,
        self.timestamp);

    _callType = callType;

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self saveWithTransaction:transaction];

        // redraw any thread-related unread count UI.
        [self touchThreadWithTransaction:transaction];
    }];
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
