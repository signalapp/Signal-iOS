//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SignalAccount.h"
#import "SignalRecipient.h"
#import "TSStorageManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface SignalAccount ()

@property (nonatomic) NSString *recipientId;

@end

#pragma mark -

@implementation SignalAccount

- (instancetype)initWithSignalRecipient:(SignalRecipient *)signalRecipient
{
    if (self = [super init]) {
        OWSAssert(signalRecipient);

        _recipientId = signalRecipient.uniqueId;
    }
    return self;
}

- (instancetype)initWithRecipientId:(NSString *)recipientId
{
    if (self = [super init]) {
        OWSAssert(recipientId.length > 0);

        _recipientId = recipientId;
    }
    return self;
}

- (nullable SignalRecipient *)signalRecipientWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(transaction);

    return [SignalRecipient recipientWithTextSecureIdentifier:self.recipientId withTransaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
