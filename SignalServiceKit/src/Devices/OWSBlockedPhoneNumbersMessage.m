//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSBlockedPhoneNumbersMessage.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSBlockedPhoneNumbersMessage ()

@property (nonatomic, readonly) NSArray<NSString *> *phoneNumbers;

@end

@implementation OWSBlockedPhoneNumbersMessage

- (instancetype)initWithPhoneNumbers:(NSArray<NSString *> *)phoneNumbers
{
    self = [super init];
    if (!self) {
        return self;
    }

    _phoneNumbers = [phoneNumbers copy];

    return self;
}

- (OWSSignalServiceProtosSyncMessageBuilder *)syncMessageBuilder
{
    OWSSignalServiceProtosSyncMessageBlockedBuilder *blockedPhoneNumbersBuilder =
        [OWSSignalServiceProtosSyncMessageBlockedBuilder new];
    [blockedPhoneNumbersBuilder setNumbersArray:_phoneNumbers];
    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];
    [syncMessageBuilder setBlocked:[blockedPhoneNumbersBuilder build]];

    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
