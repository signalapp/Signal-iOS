//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSInteraction.h>

@class YapDatabaseReadWriteTransaction;

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactOffersInteraction : TSInteraction

@property (nonatomic, readonly) BOOL hasBlockOffer;
@property (nonatomic, readonly) BOOL hasAddToContactsOffer;
@property (nonatomic, readonly) BOOL hasAddToProfileWhitelistOffer;

- (instancetype)initInteractionWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

// MJK TODO should be safe to remove this timestamp param
- (instancetype)initWithUniqueId:(NSString *)uniqueId
                        timestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                    hasBlockOffer:(BOOL)hasBlockOffer
            hasAddToContactsOffer:(BOOL)hasAddToContactsOffer
    hasAddToProfileWhitelistOffer:(BOOL)hasAddToProfileWhitelistOffer NS_DESIGNATED_INITIALIZER;


@end

NS_ASSUME_NONNULL_END
