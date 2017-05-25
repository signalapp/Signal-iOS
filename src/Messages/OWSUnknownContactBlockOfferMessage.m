//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSUnknownContactBlockOfferMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSUnknownContactBlockOfferMessage ()

@property (nonatomic) NSString *contactId;

@end

#pragma mark -

@implementation OWSUnknownContactBlockOfferMessage

+ (instancetype)unknownContactBlockOfferMessage:(uint64_t)timestamp
                                         thread:(TSThread *)thread
                                      contactId:(NSString *)contactId
{
    return [[OWSUnknownContactBlockOfferMessage alloc] initWithTimestamp:timestamp thread:thread contactId:contactId];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread contactId:(NSString *)contactId
{
    self = [super initWithTimestamp:timestamp inThread:thread failedMessageType:TSErrorMessageUnknownContactBlockOffer];

    if (self) {
        _contactId = contactId;
    }

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

@end

NS_ASSUME_NONNULL_END
