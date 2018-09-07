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

- (instancetype)initWithSignalRecipient:(SignalRecipient *)signalRecipient
{
    OWSAssertDebug(signalRecipient);
    return [self initWithRecipientId:signalRecipient.recipientId];
}

- (instancetype)initWithRecipientId:(NSString *)recipientId
{
    if (self = [super init]) {
        OWSAssertDebug(recipientId.length > 0);

        _recipientId = recipientId;
    }
    return self;
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
