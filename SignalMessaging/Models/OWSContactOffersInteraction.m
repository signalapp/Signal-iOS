//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactOffersInteraction.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSContactOffersInteraction

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initContactOffersWithTimestamp:(uint64_t)timestamp
                                        thread:(TSThread *)thread
                                 hasBlockOffer:(BOOL)hasBlockOffer
                         hasAddToContactsOffer:(BOOL)hasAddToContactsOffer
                 hasAddToProfileWhitelistOffer:(BOOL)hasAddToProfileWhitelistOffer
                                   recipientId:(NSString *)recipientId
{
    self = [super initInteractionWithTimestamp:timestamp inThread:thread];

    if (!self) {
        return self;
    }

    _hasBlockOffer = hasBlockOffer;
    _hasAddToContactsOffer = hasAddToContactsOffer;
    _hasAddToProfileWhitelistOffer = hasAddToProfileWhitelistOffer;
    OWSAssertDebug(recipientId.length > 0);
    _recipientId = recipientId;

    return self;
}

- (BOOL)shouldUseReceiptDateForSorting
{
    // Use the timestamp, not the "received at" timestamp to sort,
    // since we're creating these interactions after the fact and back-dating them.
    return NO;
}

- (BOOL)isDynamicInteraction
{
    return YES;
}

- (OWSInteractionType)interactionType
{
    return OWSInteractionType_Offer;
}

@end

NS_ASSUME_NONNULL_END
