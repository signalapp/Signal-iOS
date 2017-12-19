//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SignalAccount.h"
#import "Contact.h"
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
    OWSAssert(signalRecipient);
    return [self initWithRecipientId:signalRecipient.recipientId];
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
    OWSAssertIsOnMainThread();
    OWSAssert(transaction);

    OWSAssert(self.recipientId.length > 0);
    return [SignalRecipient recipientWithTextSecureIdentifier:self.recipientId withTransaction:transaction];
}

- (nullable NSString *)uniqueId
{
    return _recipientId;
}

- (NSString *)displayName
{
    NSString *baseName = (self.contact.fullName.length > 0 ? self.contact.fullName : self.recipientId);

    OWSAssert(self.hasMultipleAccountContact == (self.multipleAccountLabelText != nil));
    NSString *displayName = (self.multipleAccountLabelText
            ? [NSString stringWithFormat:@"%@ (%@)", baseName, self.multipleAccountLabelText]
            : baseName);

    return displayName;
}

@end

NS_ASSUME_NONNULL_END
