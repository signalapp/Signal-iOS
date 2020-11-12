//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAddToProfileWhitelistOfferMessage.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

// This is a deprecated class, we're keeping it around to avoid YapDB serialization errors
// TODO - remove this class, clean up existing instances, ensure any missed ones don't explode (UnknownDBObject)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
@implementation OWSAddToProfileWhitelistOfferMessage
#pragma clang diagnostic pop

+ (instancetype)addToProfileWhitelistOfferMessageWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread
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
