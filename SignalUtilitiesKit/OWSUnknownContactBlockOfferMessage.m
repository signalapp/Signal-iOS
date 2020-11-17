//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSUnknownContactBlockOfferMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSUnknownContactBlockOfferMessage ()

@property (nonatomic) NSString *contactId;

@end

#pragma mark -

// This is a deprecated class, we're keeping it around to avoid YapDB serialization errors
// TODO - remove this class, clean up existing instances, ensure any missed ones don't explode (UnknownDBObject)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
@implementation OWSUnknownContactBlockOfferMessage
#pragma clang diagnostic pop

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
