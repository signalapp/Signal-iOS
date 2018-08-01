//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBlockedPhoneNumbersMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSBlockedPhoneNumbersMessage ()

@property (nonatomic, readonly) NSArray<NSString *> *phoneNumbers;

@end

@implementation OWSBlockedPhoneNumbersMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithPhoneNumbers:(NSArray<NSString *> *)phoneNumbers
{
    self = [super init];
    if (!self) {
        return self;
    }

    _phoneNumbers = [phoneNumbers copy];

    return self;
}

- (SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    SSKProtoSyncMessageBlockedBuilder *blockedPhoneNumbersBuilder =
        [SSKProtoSyncMessageBlockedBuilder new];
    [blockedPhoneNumbersBuilder setNumbersArray:_phoneNumbers];
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessageBuilder new];
    [syncMessageBuilder setBlocked:[blockedPhoneNumbersBuilder build]];

    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
