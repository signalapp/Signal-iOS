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

- (nullable NSDate *)receiptDateForSorting
{
    // Always use date, since we're creating these interactions after the fact
    // and back-dating them.
    //
    // By default [TSMessage receiptDateForSorting] will prefer to use receivedAtDate
    // which is not back-dated.
    return self.date;
}

@end

NS_ASSUME_NONNULL_END
