//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAddToProfileWhitelistOfferMessage.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSAddToProfileWhitelistOfferMessage

+ (instancetype)addToProfileWhitelistOfferMessage:(uint64_t)timestamp thread:(TSThread *)thread
{
    return [[OWSAddToProfileWhitelistOfferMessage alloc]
        initWithTimestamp:timestamp
                 inThread:thread
              messageType:(thread.isGroupThread ? TSInfoMessageAddGroupToProfileWhitelistOffer
                                                : TSInfoMessageAddUserToProfileWhitelistOffer)];
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

@end

NS_ASSUME_NONNULL_END
