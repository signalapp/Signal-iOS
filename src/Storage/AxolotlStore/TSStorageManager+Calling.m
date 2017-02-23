//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+Calling.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const TSStorageManagerCallKitIdToPhoneNumberCollection = @"TSStorageManagerCallKitIdToPhoneNumberCollection";

@implementation TSStorageManager (Calling)

- (void)setPhoneNumber:(NSString *)phoneNumber forCallKitId:(NSString *)callKitId
{
    OWSAssert(phoneNumber.length > 0);
    OWSAssert(callKitId.length > 0);

    [self setObject:phoneNumber forKey:callKitId inCollection:TSStorageManagerCallKitIdToPhoneNumberCollection];
}

- (NSString *)phoneNumberForCallKitId:(NSString *)callKitId
{
    OWSAssert(callKitId.length > 0);

    return [self objectForKey:callKitId inCollection:TSStorageManagerCallKitIdToPhoneNumberCollection];
}

@end

NS_ASSUME_NONNULL_END
