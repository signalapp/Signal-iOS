//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSInteraction.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactOffersInteraction : TSInteraction

@property (nonatomic, readonly) BOOL hasBlockOffer;
@property (nonatomic, readonly) BOOL hasAddToContactsOffer;
@property (nonatomic, readonly) BOOL hasAddToProfileWhitelistOffer;
@property (nonatomic, readonly) NSString *recipientId;

- (instancetype)initInteractionWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initContactOffersWithTimestamp:(uint64_t)timestamp
                                        thread:(TSThread *)thread
                                 hasBlockOffer:(BOOL)hasBlockOffer
                         hasAddToContactsOffer:(BOOL)hasAddToContactsOffer
                 hasAddToProfileWhitelistOffer:(BOOL)hasAddToProfileWhitelistOffer
                                   recipientId:(NSString *)recipientId NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
