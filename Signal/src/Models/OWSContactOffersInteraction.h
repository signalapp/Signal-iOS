//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSInteraction.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactOffersInteraction : TSInteraction

@property (nonatomic, readonly) BOOL hasBlockOffer;
@property (nonatomic, readonly) BOOL hasAddToContactsOffer;
@property (nonatomic, readonly) BOOL hasAddToProfileWhitelistOffer;
@property (nonatomic, readonly) NSString *contactId;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                    hasBlockOffer:(BOOL)hasBlockOffer
            hasAddToContactsOffer:(BOOL)hasAddToContactsOffer
    hasAddToProfileWhitelistOffer:(BOOL)hasAddToProfileWhitelistOffer
                        contactId:(NSString *)contactId NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
