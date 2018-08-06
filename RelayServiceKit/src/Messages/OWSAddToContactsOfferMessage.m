//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAddToContactsOfferMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSAddToContactsOfferMessage ()

@property (nonatomic) NSString *contactId;

@end

#pragma mark -

@implementation OWSAddToContactsOfferMessage

+ (instancetype)addToContactsOfferMessage:(uint64_t)timestamp thread:(TSThread *)thread contactId:(NSString *)contactId
{
    return [[OWSAddToContactsOfferMessage alloc] initWithTimestamp:timestamp thread:thread contactId:contactId];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread contactId:(NSString *)contactId
{
    self = [super initWithTimestamp:timestamp inThread:thread messageType:TSInfoMessageAddToContactsOffer];

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
