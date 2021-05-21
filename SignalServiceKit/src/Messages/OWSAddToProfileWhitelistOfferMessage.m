//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSAddToProfileWhitelistOfferMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

// TODO: Cull?
// This is a deprecated class, we're keeping it around to avoid YapDB serialization errors
// TODO - remove this class, clean up existing instances, ensure any missed ones don't explode (UnknownDBObject)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
@implementation OWSAddToProfileWhitelistOfferMessage
#pragma clang diagnostic pop

// --- CODE GENERATION MARKER

// --- CODE GENERATION MARKER

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
