//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSInteraction.h>

@class YapDatabaseReadWriteTransaction;

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactOffersInteraction : TSInteraction

@property (nonatomic, readonly) BOOL hasBlockOffer;
@property (nonatomic, readonly) BOOL hasAddToContactsOffer;
@property (nonatomic, readonly) BOOL hasAddToProfileWhitelistOffer;

// TODO - remove this recipientId param
// it's redundant with the interaction's TSContactThread
@property (nonatomic, readonly) NSString *recipientId;

- (instancetype)initInteractionWithSenderTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

// MJK TODO Remove this timestamp param?
- (instancetype)initContactOffersWithSenderTimestamp:(uint64_t)timestamp
                                              thread:(TSThread *)thread
                                       hasBlockOffer:(BOOL)hasBlockOffer
                               hasAddToContactsOffer:(BOOL)hasAddToContactsOffer
                       hasAddToProfileWhitelistOffer:(BOOL)hasAddToProfileWhitelistOffer
                                         recipientId:(NSString *)recipientId NS_DESIGNATED_INITIALIZER;

- (void)updateHasBlockOffer:(BOOL)hasBlockOffer
            hasAddToContactsOffer:(BOOL)hasAddToContactsOffer
    hasAddToProfileWhitelistOffer:(BOOL)hasAddToProfileWhitelistOffer
                      transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
