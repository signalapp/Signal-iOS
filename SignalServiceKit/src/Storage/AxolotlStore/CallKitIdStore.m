//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "CallKitIdStore.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation CallKitIdStore

+ (SDSKeyValueStore *)phoneNumberStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerCallKitIdToPhoneNumberCollection"];
}

+ (SDSKeyValueStore *)uuidStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerCallKitIdToUUIDCollection"];
}

+ (SDSKeyValueStore *)groupIdStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerCallKitIdToGroupId"];
}

#pragma mark -

+ (void)setThread:(TSThread *)thread forCallKitId:(NSString *)callKitId
{
    OWSAssertDebug(callKitId.length > 0);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        TSGroupModel *groupModel = [thread groupModelIfGroupThread];
        if (groupModel) {
            [self.groupIdStore setData:groupModel.groupId key:callKitId transaction:transaction];
            // This is probably overkill since we currently generate these IDs randomly,
            // but better futureproof than sorry.
            [self.uuidStore removeValueForKey:callKitId transaction:transaction];
            [self.phoneNumberStore removeValueForKey:callKitId transaction:transaction];
        } else {
            OWSAssertDebug([thread isKindOfClass:[TSContactThread class]]);
            SignalServiceAddress *address = [(TSContactThread *)thread contactAddress];
            NSString *uuidString = address.uuidString;
            if (uuidString) {
                [self.uuidStore setString:uuidString key:callKitId transaction:transaction];
                [self.phoneNumberStore removeValueForKey:callKitId transaction:transaction];
            } else {
                OWSFailDebug(@"making a call to an address with no UUID: %@", address.phoneNumber);
                [self.phoneNumberStore setString:address.phoneNumber key:callKitId transaction:transaction];
                [self.uuidStore removeValueForKey:callKitId transaction:transaction];
            }

            [self.groupIdStore removeValueForKey:callKitId transaction:transaction];
        }
    });
}

+ (nullable TSThread *)threadForCallKitId:(NSString *)callKitId
{
    OWSAssertDebug(callKitId.length > 0);

    __block TSThread *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        // Most likely: modern 1:1 calls
        NSString *_Nullable uuidString = [self.uuidStore getString:callKitId transaction:transaction];
        if (uuidString) {
            SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithUuidString:uuidString];
            result = [TSContactThread getThreadWithContactAddress:address transaction:transaction];
            return;
        }

        // Next try group calls
        NSData *_Nullable groupId = [self.groupIdStore getData:callKitId transaction:transaction];
        if (groupId) {
            result = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
            return;
        }

        // Finally check the phone number store, for very old 1:1 calls.
        NSString *_Nullable phoneNumber = [self.phoneNumberStore getString:callKitId transaction:transaction];
        if (phoneNumber) {
            SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber];
            result = [TSContactThread getThreadWithContactAddress:address transaction:transaction];
            return;
        }
    }];

    return result;
}

@end

NS_ASSUME_NONNULL_END
