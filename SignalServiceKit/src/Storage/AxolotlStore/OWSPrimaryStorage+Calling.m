//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage+Calling.h"
#import "YapDatabaseConnection+OWS.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSPrimaryStorageCallKitIdToPhoneNumberCollection = @"TSStorageManagerCallKitIdToPhoneNumberCollection";
NSString *const OWSPrimaryStorageCallKitIdToUUIDCollection = @"TSStorageManagerCallKitIdToUUIDCollection";

@implementation OWSPrimaryStorage (Calling)

- (void)setAddress:(SignalServiceAddress *)address forCallKitId:(NSString *)callKitId
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(callKitId.length > 0);

    if (address.phoneNumber) {
        [self.dbReadWriteConnection setObject:address.phoneNumber
                                       forKey:callKitId
                                 inCollection:OWSPrimaryStorageCallKitIdToPhoneNumberCollection];
    } else {
        [self.dbReadWriteConnection removeObjectForKey:callKitId
                                          inCollection:OWSPrimaryStorageCallKitIdToPhoneNumberCollection];
    }

    if (address.uuidString) {
        [self.dbReadWriteConnection setObject:address.uuidString
                                       forKey:callKitId
                                 inCollection:OWSPrimaryStorageCallKitIdToUUIDCollection];
    } else {
        [self.dbReadWriteConnection removeObjectForKey:callKitId
                                          inCollection:OWSPrimaryStorageCallKitIdToUUIDCollection];
    }
}

- (SignalServiceAddress *)addressForCallKitId:(NSString *)callKitId
{
    OWSAssertDebug(callKitId.length > 0);

    NSString *_Nullable phoneNumber =
        [self.dbReadConnection objectForKey:callKitId inCollection:OWSPrimaryStorageCallKitIdToPhoneNumberCollection];
    NSString *_Nullable uuidString = [self.dbReadConnection objectForKey:callKitId
                                                            inCollection:OWSPrimaryStorageCallKitIdToUUIDCollection];

    if (!phoneNumber && !uuidString) {
        return nil;
    }

    return [[SignalServiceAddress alloc] initWithUuidString:uuidString phoneNumber:phoneNumber];
}

@end

NS_ASSUME_NONNULL_END
