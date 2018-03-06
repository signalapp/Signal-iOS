//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage+Calling.h"
#import "YapDatabaseConnection+OWS.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSPrimaryStorageCallKitIdToPhoneNumberCollection = @"TSStorageManagerCallKitIdToPhoneNumberCollection";

@implementation OWSPrimaryStorage (Calling)

- (void)setPhoneNumber:(NSString *)phoneNumber forCallKitId:(NSString *)callKitId
{
    OWSAssert(phoneNumber.length > 0);
    OWSAssert(callKitId.length > 0);

    [self.dbReadWriteConnection setObject:phoneNumber
                                   forKey:callKitId
                             inCollection:OWSPrimaryStorageCallKitIdToPhoneNumberCollection];
}

- (NSString *)phoneNumberForCallKitId:(NSString *)callKitId
{
    OWSAssert(callKitId.length > 0);

    return
        [self.dbReadConnection objectForKey:callKitId inCollection:OWSPrimaryStorageCallKitIdToPhoneNumberCollection];
}

@end

NS_ASSUME_NONNULL_END
