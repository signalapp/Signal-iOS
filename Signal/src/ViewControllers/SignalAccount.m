//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SignalAccount.h"
#import <SignalServiceKit/SignalRecipient.h>
#import <SignalServiceKit/TSStorageManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface SignalAccount ()

@property (nonatomic, nullable) SignalRecipient *signalRecipient;

// This property may be modified after construction, so it should
// only be modified on the main thread.
@property (nonatomic) NSString *recipientId;

@end

#pragma mark -

@implementation SignalAccount

- (instancetype)initWithSignalRecipient:(SignalRecipient *)signalRecipient
{
    if (self = [super init]) {
        OWSAssert(signalRecipient);

        _signalRecipient = signalRecipient;
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

- (nullable SignalRecipient *)signalRecipient
{
    OWSAssert([NSThread isMainThread]);

    if (!_signalRecipient) {
        [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            _signalRecipient =
                [SignalRecipient recipientWithTextSecureIdentifier:self.recipientId withTransaction:transaction];
        }];
    }

    return _signalRecipient;
}

@end

NS_ASSUME_NONNULL_END
