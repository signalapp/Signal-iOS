//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugContactsUtils.h"
#import "Signal-Swift.h"
#import <Contacts/Contacts.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef USE_DEBUG_UI

@implementation DebugContactsUtils

+ (NSString *)randomPhoneNumber
{
    if (arc4random_uniform(2) == 0) {
        // Generate a US phone number.
        NSMutableString *result = [@"+1" mutableCopy];
        for (int i = 0; i < 10; i++) {
            // Add digits.
            [result appendString:[@(arc4random_uniform(10)) description]];
        }
        return result;
    } else {
        // Generate a UK phone number.
        NSMutableString *result = [@"+441" mutableCopy];
        for (int i = 0; i < 9; i++) {
            // Add digits.
            [result appendString:[@(arc4random_uniform(10)) description]];
        }
        return result;
    }
}

+ (void)createRandomContacts:(NSUInteger)count
{
    [self createRandomContacts:count contactHandler:nil];
}

+ (void)createRandomContacts:(NSUInteger)count
              contactHandler:
                  (nullable void (^)(CNContact *_Nonnull contact, NSUInteger idx, BOOL *_Nonnull stop))contactHandler
{
    OWSAssertDebug(count > 0);

    NSUInteger remainder = count;
    const NSUInteger kMaxBatchSize = 10;
    NSUInteger batch = MIN(kMaxBatchSize, remainder);
    remainder -= batch;
    [self createRandomContactsBatch:batch
                     contactHandler:contactHandler
             batchCompletionHandler:^{
                 if (remainder > 0) {
                     dispatch_async(dispatch_get_main_queue(), ^{
                         [self createRandomContacts:remainder contactHandler:contactHandler];
                     });
                 }
             }];
}

+ (void)createRandomContactsBatch:(NSUInteger)count
                   contactHandler:(nullable void (^)(
                                      CNContact *_Nonnull contact, NSUInteger idx, BOOL *_Nonnull stop))contactHandler
           batchCompletionHandler:(nullable void (^)(void))batchCompletionHandler
{
    OWSAssertDebug(count > 0);
    OWSAssertDebug(batchCompletionHandler);

    OWSLogDebug(@"createRandomContactsBatch: %zu", count);

    CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    if (status == CNAuthorizationStatusDenied || status == CNAuthorizationStatusRestricted) {
        [OWSActionSheets showActionSheetWithTitle:@"Error" message:@"No contacts access."];
        return;
    }

    NSMutableArray<CNContact *> *contacts = [NSMutableArray new];
    CNContactStore *store = [[CNContactStore alloc] init];
    [store requestAccessForEntityType:CNEntityTypeContacts
                    completionHandler:^(BOOL granted, NSError *_Nullable error) {
                        if (!granted || error) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [OWSActionSheets showActionSheetWithTitle:@"Error" message:@"No contacts access."];
                            });
                            return;
                        }

                        CNSaveRequest *request = [[CNSaveRequest alloc] init];
                        for (NSUInteger i = 0; i < count; i++) {
                            @autoreleasepool {
                                CNMutableContact *contact = [[CNMutableContact alloc] init];
                                // Include a wellknown so we can later clear these fake entries from the
                                // system contacts.
                                contact.familyName = [@"Rando-" stringByAppendingString:[CommonGenerator lastName]];
                                contact.givenName = [CommonGenerator firstName];

                                NSString *phoneString = [self randomPhoneNumber];
                                CNLabeledValue *homePhone = [CNLabeledValue
                                    labeledValueWithLabel:CNLabelHome
                                                    value:[CNPhoneNumber phoneNumberWithStringValue:phoneString]];
                                contact.phoneNumbers = @[ homePhone ];

                                // 50% chance of fake contact having an avatar
                                const NSUInteger kPercentWithAvatar = 50;
                                const NSUInteger kPercentWithLargeAvatar = 25;
                                const NSUInteger kMinimumAvatarDiameter = 200;
                                const NSUInteger kMaximumAvatarDiameter = 800;
                                OWSAssertDebug(kMaximumAvatarDiameter >= kMinimumAvatarDiameter);
                                uint32_t avatarSeed = arc4random_uniform(100);
                                if (avatarSeed < kPercentWithAvatar) {
                                    BOOL shouldUseLargeAvatar = avatarSeed < kPercentWithLargeAvatar;
                                    NSUInteger avatarDiameter;
                                    if (shouldUseLargeAvatar) {
                                        avatarDiameter = kMaximumAvatarDiameter;
                                    } else {
                                        avatarDiameter
                                            = arc4random_uniform(kMaximumAvatarDiameter - kMinimumAvatarDiameter)
                                            + kMinimumAvatarDiameter;
                                    }
                                    // Note this doesn't work on iOS9, since iOS9 doesn't generate the
                                    // imageThumbnailData from programmatically assigned imageData. We could make our
                                    // own thumbnail in Contact.m, but it's not worth it for the sake of debug UI.
                                    UIImage *avatarImage = (shouldUseLargeAvatar
                                            ? [AvatarBuilder buildNoiseAvatarWithDiameterPoints:avatarDiameter]
                                            : [AvatarBuilder buildRandomAvatarWithDiameterPoints:avatarDiameter]);
                                    contact.imageData = UIImageJPEGRepresentation(avatarImage, (CGFloat)0.9);
                                    OWSLogDebug(@"avatar size: %lu bytes", (unsigned long)contact.imageData.length);
                                }

                                [contacts addObject:contact];
                                [request addContact:contact toContainerWithIdentifier:nil];
                            }
                        }

                        OWSLogInfo(@"Saving fake contacts: %zu", contacts.count);

                        NSError *saveError = nil;
                        if (![store executeSaveRequest:request error:&saveError]) {
                            OWSFailDebug(@"Error saving fake contacts: %@", saveError);
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [OWSActionSheets showActionSheetWithTitle:@"Error"
                                                                  message:saveError.userErrorDescription];
                            });
                            return;
                        } else {
                            if (contactHandler) {
                                [contacts enumerateObjectsUsingBlock:contactHandler];
                            }
                        }
                        if (batchCompletionHandler) {
                            batchCompletionHandler();
                        }
                    }];
}

+ (void)deleteContactsWithFilter:(BOOL (^_Nonnull)(CNContact *contact))filterBlock
{
    OWSAssertDebug(filterBlock);

    CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    if (status == CNAuthorizationStatusDenied || status == CNAuthorizationStatusRestricted) {
        [OWSActionSheets showActionSheetWithTitle:@"Error" message:@"No contacts access."];
        return;
    }

    CNContactStore *store = [[CNContactStore alloc] init];
    [store requestAccessForEntityType:CNEntityTypeContacts
                    completionHandler:^(BOOL granted, NSError *_Nullable error) {
                        if (!granted || error) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [OWSActionSheets showActionSheetWithTitle:@"Error" message:@"No contacts access."];
                            });
                            return;
                        }

                        CNContactFetchRequest *fetchRequest = [[CNContactFetchRequest alloc] initWithKeysToFetch:@[
                            CNContactIdentifierKey,
                            CNContactGivenNameKey,
                            CNContactFamilyNameKey,
                            [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName],
                        ]];
                        CNSaveRequest *request = [[CNSaveRequest alloc] init];
                        NSError *fetchError = nil;
                        BOOL result =
                            [store enumerateContactsWithFetchRequest:fetchRequest
                                                               error:&fetchError
                                                          usingBlock:^(CNContact *contact, BOOL *stop) {
                                                              if (filterBlock(contact)) {
                                                                  [request deleteContact:[contact mutableCopy]];
                                                              }
                                                          }];

                        NSError *saveError = nil;
                        if (!result || fetchError) {
                            OWSLogError(@"error = %@", fetchError);
                            [OWSActionSheets showActionSheetWithTitle:@"Error" message:fetchError.userErrorDescription];
                        } else if (![store executeSaveRequest:request error:&saveError]) {
                            OWSLogError(@"error = %@", saveError);
                            [OWSActionSheets showActionSheetWithTitle:@"Error" message:saveError.userErrorDescription];
                        }
                    }];
}

+ (void)deleteAllContacts
{
    [self deleteContactsWithFilter:^(CNContact *contact) {
        return YES;
    }];
}

+ (void)deleteAllRandomContacts
{
    [self deleteContactsWithFilter:^(CNContact *contact) {
        return [contact.familyName hasPrefix:@"Rando-"];
    }];
}

@end

#endif

NS_ASSUME_NONNULL_END
