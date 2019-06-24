//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SignalAccountFinder.h"
#import "OWSPrimaryStorage.h"
#import "SignalAccount.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseQuery.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const SignalAccountFinderRecipientPhoneNumberColumn = @"recipient_phone_number";
static NSString *const SignalAccountFinderRecipientUUIDColumn = @"recipient_uuid";

static NSString *const SignalAccountFinderUUIDAndPhoneNumberIndex
    = @"index_messages_on_recipient_uuid_and_phone_number";


@implementation SignalAccountFinder

- (nullable SignalAccount *)signalAccountForAddress:(SignalServiceAddress *)address
                                    withTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(address);
    OWSAssertDebug(transaction);

    NSString *columnName = address.isPhoneNumber ? SignalAccountFinderRecipientPhoneNumberColumn
                                                 : SignalAccountFinderRecipientUUIDColumn;

    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ = \"%@\"", columnName, address.stringIdentifier];

    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];

    __block SignalAccount *_Nullable account;
    [[transaction ext:SignalAccountFinderUUIDAndPhoneNumberIndex]
        enumerateKeysAndObjectsMatchingQuery:query
                                  usingBlock:^void(NSString *collection, NSString *key, id object, BOOL *stop) {
                                      if (![object isKindOfClass:[SignalAccount class]]) {
                                          OWSFailDebug(@"Object was unexpected class: %@", [object class]);
                                          return;
                                      }

                                      account = (SignalAccount *)object;
                                      *stop = YES;
                                  }];

    return account;
}

#pragma mark - YapDatabaseExtension

+ (YapDatabaseSecondaryIndex *)indexDatabaseExtension
{
    YapDatabaseSecondaryIndexSetup *setup = [YapDatabaseSecondaryIndexSetup new];
    [setup addColumn:SignalAccountFinderRecipientUUIDColumn withType:YapDatabaseSecondaryIndexTypeText];
    [setup addColumn:SignalAccountFinderRecipientPhoneNumberColumn withType:YapDatabaseSecondaryIndexTypeText];

    YapDatabaseSecondaryIndexHandler *handler =
        [YapDatabaseSecondaryIndexHandler withObjectBlock:^(YapDatabaseReadTransaction *transaction,
            NSMutableDictionary *dict,
            NSString *collection,
            NSString *key,
            id object) {
            if (![object isKindOfClass:[SignalAccount class]]) {
                return;
            }
            SignalAccount *account = (SignalAccount *)object;
            dict[SignalAccountFinderRecipientUUIDColumn] = account.recipientUUID;
            dict[SignalAccountFinderRecipientPhoneNumberColumn] = account.recipientPhoneNumber;
        }];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler versionTag:@"1"];
}

+ (void)asyncRegisterDatabaseExtensions:(OWSStorage *)storage
{
    [storage asyncRegisterExtension:[self indexDatabaseExtension] withName:SignalAccountFinderUUIDAndPhoneNumberIndex];
}

@end

NS_ASSUME_NONNULL_END
