//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalAccount.h"
#import "Contact.h"
#import "NSString+SSK.h"
#import "OWSPrimaryStorage.h"
#import "SignalRecipient.h"

NS_ASSUME_NONNULL_BEGIN

@interface SignalAccount ()

@property (nonatomic) NSString *recipientId;

@end

#pragma mark -

@implementation SignalAccount

+ (NSString *)collection
{
    return @"SignalAccount2";
}

+ (NSString *)collection_old
{
    return @"SignalAccount";
}

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

- (nullable NSString *)contactFullName
{
    return self.contact.fullName.filterStringForDisplay;
}

- (NSString *)multipleAccountLabelText
{
    return _multipleAccountLabelText.filterStringForDisplay;
}

@end

NS_ASSUME_NONNULL_END
