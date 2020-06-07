//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "CallKitIdStore.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation CallKitIdStore

#pragma mark - Dependencies

+ (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

+ (SDSKeyValueStore *)phoneNumberStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerCallKitIdToPhoneNumberCollection"];
}

+ (SDSKeyValueStore *)uuidStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerCallKitIdToUUIDCollection"];
}

#pragma mark -

+ (void)setAddress:(SignalServiceAddress *)address forCallKitId:(NSString *)callKitId
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(callKitId.length > 0);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        if (address.phoneNumber) {
            [self.phoneNumberStore setString:address.phoneNumber key:callKitId transaction:transaction];
        } else {
            [self.phoneNumberStore removeValueForKey:callKitId transaction:transaction];
        }

        if (address.uuidString) {
            [self.uuidStore setString:address.uuidString key:callKitId transaction:transaction];
        } else {
            [self.uuidStore removeValueForKey:callKitId transaction:transaction];
        }
    });
}

+ (SignalServiceAddress *)addressForCallKitId:(NSString *)callKitId
{
    OWSAssertDebug(callKitId.length > 0);

    __block NSString *_Nullable phoneNumber;
    __block NSString *_Nullable uuidString;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        phoneNumber = [self.phoneNumberStore getString:callKitId transaction:transaction];
        uuidString = [self.uuidStore getString:callKitId transaction:transaction];
    }];

    if (!phoneNumber && !uuidString) {
        return nil;
    }

    return [[SignalServiceAddress alloc] initWithUuidString:uuidString phoneNumber:phoneNumber];
}

@end

NS_ASSUME_NONNULL_END
