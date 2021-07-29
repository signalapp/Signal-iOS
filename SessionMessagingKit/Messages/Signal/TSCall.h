//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SessionMessagingKit/OWSReadTracking.h>
#import <SessionMessagingKit/TSInteraction.h>

NS_ASSUME_NONNULL_BEGIN

@class TSContactThread;

typedef NS_ENUM(NSUInteger, RPRecentCallType) {
    RPRecentCallTypeIncoming = 1,
    RPRecentCallTypeOutgoing,
    RPRecentCallTypeIncomingMissed,
    // These call types are used until the call connects.
    RPRecentCallTypeOutgoingIncomplete,
    RPRecentCallTypeIncomingIncomplete,
    RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity,
    RPRecentCallTypeIncomingDeclined,
    RPRecentCallTypeOutgoingMissed,
    RPRecentCallTypeIncomingAnsweredElsewhere,
    RPRecentCallTypeIncomingDeclinedElsewhere,
    RPRecentCallTypeIncomingBusyElsewhere
};

typedef NS_CLOSED_ENUM(NSUInteger, TSRecentCallOfferType) { TSRecentCallOfferTypeAudio, TSRecentCallOfferTypeVideo };

NSString *NSStringFromCallType(RPRecentCallType callType);

@interface TSCall : TSInteraction <OWSReadTracking, OWSPreviewText>

@property (nonatomic, readonly) RPRecentCallType callType;
@property (nonatomic, readonly) TSRecentCallOfferType offerType;

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                       timestamp:(uint64_t)timestamp
                          thread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithUniqueId:(NSString *)uniqueId
                       timestamp:(uint64_t)timestamp
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          thread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initInteractionWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCallType:(RPRecentCallType)callType
                       offerType:(TSRecentCallOfferType)offerType
                          thread:(TSContactThread *)thread
                 sentAtTimestamp:(uint64_t)sentAtTimestamp NS_DESIGNATED_INITIALIZER;


- (void)updateCallType:(RPRecentCallType)callType;
- (void)updateCallType:(RPRecentCallType)callType transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
