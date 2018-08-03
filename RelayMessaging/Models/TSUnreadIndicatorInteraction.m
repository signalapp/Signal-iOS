//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSUnreadIndicatorInteraction.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSUnreadIndicatorInteraction

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
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
    return OWSInteractionType_Unknown;
}

@end

NS_ASSUME_NONNULL_END
