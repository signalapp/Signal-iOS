//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSContactsManager.h"
#import "Environment.h"
#import "OWSProfileManager.h"
#import <Contacts/Contacts.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const OWSContactsManagerSignalAccountsDidChangeNotification
= @"OWSContactsManagerSignalAccountsDidChangeNotification";
NSNotificationName const OWSContactsManagerContactsDidChangeNotification
= @"OWSContactsManagerContactsDidChangeNotification";

NSString *const OWSContactsManagerCollection = @"OWSContactsManagerCollection";
NSString *const OWSContactsManagerKeyLastKnownContactPhoneNumbers
= @"OWSContactsManagerKeyLastKnownContactPhoneNumbers";
NSString *const OWSContactsManagerKeyNextFullIntersectionDate = @"OWSContactsManagerKeyNextFullIntersectionDate2";

@interface OWSContactsManager () <SystemContactsFetcherDelegate>

@property (nonatomic) BOOL isContactsUpdateInFlight;

@property (nonatomic, readonly) SystemContactsFetcher *systemContactsFetcher;
@property (nonatomic, readonly) AnyLRUCache *cnContactCache;
@property (atomic) BOOL isSetup;

@end

#pragma mark -

@implementation OWSContactsManager

- (id)init
{
    self = [super init];
    if (!self) {
        return self;
    }
    
    _keyValueStore = [[SDSKeyValueStore alloc] initWithCollection:OWSContactsManagerCollection];
    
    _systemContactsFetcher = [SystemContactsFetcher new];
    _systemContactsFetcher.delegate = self;
    _cnContactCache = [[AnyLRUCache alloc] initWithMaxSize:50
                                                nseMaxSize:0
                                shouldEvacuateInBackground:YES];
    if (CurrentAppContext().isMainApp) {
        _contactsManagerCache = [ContactsManagerCacheInMemory new];
    } else {
        _contactsManagerCache = [ContactsManagerCacheInDatabase new];
    }
    
    OWSSingletonAssert();
    
    AppReadinessRunNowOrWhenAppWillBecomeReady(^{
        [self setup];
    });
    
    return self;
}

- (void)setup {
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        ContactsManagerCacheSummary *contactsManagerCacheSummary = [self.contactsManagerCache warmCachesWithTransaction:transaction];
        OWSLogInfo(@"There are %lu phone numbers and %lu signal accounts.",
            (unsigned long)contactsManagerCacheSummary.phoneNumberCount,
            (unsigned long)contactsManagerCacheSummary.signalAccountCount);
    } file:__FILE__ function:__FUNCTION__ line:__LINE__];

    self.isSetup = YES;
}

#pragma mark - Sharing Contacts

- (ContactAuthorizationForSharing)sharingAuthorization
{
    switch (self.systemContactsFetcher.rawAuthorizationStatus) {
        case RawContactAuthorizationStatusNotDetermined:
            return ContactAuthorizationForSharingNotDetermined;

        case RawContactAuthorizationStatusDenied:
        case RawContactAuthorizationStatusRestricted:
            return ContactAuthorizationForSharingDenied;

        case RawContactAuthorizationStatusAuthorized:
            return ContactAuthorizationForSharingAuthorized;
    }
}

#pragma mark - Editing/Syncing Contacts

- (BOOL)isEditingAllowed
{
    return !SSKFeatureFlags.contactDiscoveryV2 || self.tsAccountManager.isPrimaryDevice;
}

- (ContactAuthorizationForEditing)editingAuthorization
{
    if (![self isEditingAllowed]) {
        return ContactAuthorizationForEditingNotAllowed;
    }
    switch (self.systemContactsFetcher.rawAuthorizationStatus) {
        case RawContactAuthorizationStatusNotDetermined:
            OWSFailDebug(@"should have called `requestOnce` before checking authorization status.");
            // fallthrough
        case RawContactAuthorizationStatusDenied:
            return ContactAuthorizationForEditingDenied;

        case RawContactAuthorizationStatusRestricted:
            return ContactAuthorizationForEditingRestricted;

        case RawContactAuthorizationStatusAuthorized:
            return ContactAuthorizationForEditingAuthorized;
    }
}

// Request contacts access if you haven't asked recently.
- (void)requestSystemContactsOnce
{
    [self requestSystemContactsOnceWithCompletion:nil];
}

- (void)requestSystemContactsOnceWithCompletion:(void (^_Nullable)(NSError *_Nullable error))completion
{
    OWSAssertIsOnMainThread();

    if (![self isEditingAllowed]) {
        if (completion != nil) {
            completion(OWSErrorMakeGenericError(@"Editing contacts isn't available on linked devices."));
        }
        return;
    }
    [self.systemContactsFetcher requestOnceWithCompletion:completion];
}

- (void)fetchSystemContactsOnceIfAlreadyAuthorized
{
    if (![self isEditingAllowed]) {
        return;
    }
    [self.systemContactsFetcher fetchOnceIfAlreadyAuthorized];
}

- (AnyPromise *)userRequestedSystemContactsRefresh
{
    if (![self isEditingAllowed]) {
        return [AnyPromise
            promiseWithError:OWSErrorMakeAssertionError(@"Editing contacts isn't available on linked devices.")];
    }
    return AnyPromise.withFuture(^(AnyFuture *future) {
        [self.systemContactsFetcher userRequestedRefreshWithCompletion:^(NSError *error) {
            if (error) {
                OWSLogError(@"refreshing contacts failed with error: %@", error);
                [future rejectWithError:error];
            } else {
                [future resolveWithValue:@1];
            }
        }];
    });
}

#pragma mark - CNContacts

- (nullable CNContact *)cnContactWithId:(nullable NSString *)contactId
{
    if (!contactId) {
        return nil;
    }
    
    CNContact *_Nullable cnContact = (CNContact *)[self.cnContactCache objectForKey:contactId];
    if (cnContact != nil) {
        return cnContact;
    }
    cnContact = [self.systemContactsFetcher fetchCNContactWithContactId:contactId];
    if (cnContact != nil) {
        [self.cnContactCache setObject:cnContact forKey:contactId];
    }
    return cnContact;
}

- (nullable NSData *)avatarDataForCNContactId:(nullable NSString *)contactId
{
    // Don't bother to cache avatar data.
    CNContact *_Nullable cnContact = [self cnContactWithId:contactId];
    return [Contact avatarDataForCNContact:cnContact];
}

- (nullable UIImage *)avatarImageForCNContactId:(nullable NSString *)contactId
{
    if (contactId == nil) {
        return nil;
    }
    NSData *_Nullable avatarData = [self avatarDataForCNContactId:contactId];
    if (avatarData == nil) {
        return nil;
    }
    if ([avatarData ows_isValidImage]) {
        OWSLogWarn(@"Invalid image.");
        return nil;
    }
    UIImage *_Nullable avatarImage = [UIImage imageWithData:avatarData];
    if (avatarImage == nil) {
        OWSLogWarn(@"Could not load image.");
        return nil;
    }
    return avatarImage;
}

#pragma mark - SystemContactsFetcherDelegate

- (void)systemContactsFetcher:(SystemContactsFetcher *)systemsContactsFetcher
              updatedContacts:(NSArray<Contact *> *)contacts
              isUserRequested:(BOOL)isUserRequested
{
    if (![self isEditingAllowed]) {
        OWSFailDebug(@"Syncing contacts isn't available on linked devices.");
        return;
    }
    [self updateWithContacts:contacts isUserRequested:isUserRequested];
}

- (void)systemContactsFetcher:(SystemContactsFetcher *)systemContactsFetcher
       hasAuthorizationStatus:(RawContactAuthorizationStatus)authorizationStatus
{
    if (![self isEditingAllowed]) {
        OWSFailDebug(@"Syncing contacts isn't available on linked devices.");
        return;
    }
    switch (authorizationStatus) {
        case RawContactAuthorizationStatusRestricted:
        case RawContactAuthorizationStatusDenied:
            // Clear the contacts cache if access to the system contacts is revoked.
            [self updateWithContacts:@[] isUserRequested:NO];
        case RawContactAuthorizationStatusNotDetermined:
        case RawContactAuthorizationStatusAuthorized:
            break;
    }
}

#pragma mark - Intersection

- (NSSet<NSString *> *)phoneNumbersForIntersectionWithContacts:(NSArray<Contact *> *)contacts
{
    OWSAssertDebug(contacts);
    
    NSMutableSet<NSString *> *phoneNumbers = [NSMutableSet set];
    
    for (Contact *contact in contacts) {
        [phoneNumbers addObjectsFromArray:contact.e164sForIntersection];
    }
    return [phoneNumbers copy];
}

- (void)intersectContacts:(NSArray<Contact *> *)contacts
          isUserRequested:(BOOL)isUserRequested
               completion:(void (^)(NSError *_Nullable error))completion
{
    OWSAssertDebug(contacts);
    OWSAssertDebug(completion);
    
    dispatch_async(self.intersectionQueue, ^{
        __block BOOL isFullIntersection = YES;
        __block BOOL isRegularlyScheduledRun = NO;
        __block NSSet<NSString *> *allContactPhoneNumbers;
        __block NSSet<NSString *> *phoneNumbersForIntersection;
        __block NSMutableSet<SignalRecipient *> *existingRegisteredRecipients = [NSMutableSet new];
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            // Contact updates initiated by the user should always do a full intersection.
            if (!isUserRequested) {
                NSDate *_Nullable nextFullIntersectionDate =
                [self.keyValueStore getDate:OWSContactsManagerKeyNextFullIntersectionDate transaction:transaction];
                if (nextFullIntersectionDate && [nextFullIntersectionDate isAfterNow]) {
                    isFullIntersection = NO;
                } else {
                    isRegularlyScheduledRun = YES;
                }
            }
            
            [SignalRecipient anyEnumerateWithTransaction:transaction
                                                   block:^(SignalRecipient *signalRecipient, BOOL *stop) {
                if (signalRecipient.devices.count > 0) {
                    [existingRegisteredRecipients addObject:signalRecipient];
                }
            }];
            
            allContactPhoneNumbers = [self phoneNumbersForIntersectionWithContacts:contacts];
            phoneNumbersForIntersection = allContactPhoneNumbers;
            
            if (!isFullIntersection) {
                // Do a "delta" intersection instead of a "full" intersection:
                // only intersect new contacts which were not in the last successful
                // "full" intersection.
                NSSet<NSString *> *_Nullable lastKnownContactPhoneNumbers =
                [self.keyValueStore getObjectForKey:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                        transaction:transaction];
                if (lastKnownContactPhoneNumbers) {
                    // Do a "delta" sync which only intersects phone numbers not included
                    // in the last full intersection.
                    NSMutableSet<NSString *> *newPhoneNumbers = [allContactPhoneNumbers mutableCopy];
                    [newPhoneNumbers minusSet:lastKnownContactPhoneNumbers];
                    phoneNumbersForIntersection = newPhoneNumbers;
                } else {
                    // Without a list of "last known" contact phone numbers, we'll have to do a full intersection.
                    isFullIntersection = YES;
                }
            }
        } file:__FILE__ function:__FUNCTION__ line:__LINE__];
        OWSAssertDebug(phoneNumbersForIntersection);
        
        if (phoneNumbersForIntersection.count < 1) {
            OWSLogInfo(@"Skipping intersection; no contacts to intersect.");
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(nil);
            });
            return;
        } else if (isFullIntersection) {
            OWSLogInfo(@"Doing full intersection with %zu contacts.", phoneNumbersForIntersection.count);
        } else {
            OWSLogInfo(@"Doing delta intersection with %zu contacts.", phoneNumbersForIntersection.count);
        }
        
        [self intersectContacts:phoneNumbersForIntersection
              retryDelaySeconds:1.0
                        success:^(NSSet<SignalRecipient *> *registeredRecipients) {
            if (isRegularlyScheduledRun) {
                NSMutableSet<SignalRecipient *> *newSignalRecipients = [registeredRecipients mutableCopy];
                [newSignalRecipients minusSet:existingRegisteredRecipients];
                
                if (newSignalRecipients.count == 0) {
                    OWSLogInfo(@"No new recipients.");
                } else {
                    __block NSSet<NSString *> *_Nullable lastKnownContactPhoneNumbers;
                    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
                        lastKnownContactPhoneNumbers =
                        [self.keyValueStore getObjectForKey:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                                transaction:transaction];
                    }];
                    
                    if (lastKnownContactPhoneNumbers != nil && lastKnownContactPhoneNumbers.count > 0) {
                        [OWSNewAccountDiscovery.shared discoveredNewRecipients:newSignalRecipients];
                    } else {
                        OWSLogInfo(@"skipping new recipient notification for first successful contact sync.");
                    }
                }
            }
            
            [self markIntersectionAsComplete:allContactPhoneNumbers isFullIntersection:isFullIntersection];
            
            completion(nil);
        }
                        failure:^(NSError *error) {
            completion(error);
        }];
    });
}

- (void)markIntersectionAsComplete:(NSSet<NSString *> *)phoneNumbersForIntersection
                isFullIntersection:(BOOL)isFullIntersection
{
    OWSAssertDebug(phoneNumbersForIntersection.count > 0);
    
    dispatch_async(self.intersectionQueue, ^{
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            if (isFullIntersection) {
                // replace last known numbers
                [self.keyValueStore setObject:phoneNumbersForIntersection
                                          key:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                  transaction:transaction];
                
                const NSUInteger contactCount = phoneNumbersForIntersection.count;
                
                NSDate *nextFullIntersectionDate = [NSDate dateWithTimeIntervalSinceNow:RemoteConfig.cdsSyncInterval];
                OWSLogDebug(@"contactCount: %lu, currentDate: %@, nextFullIntersectionDate: %@",
                            (unsigned long)contactCount,
                            [NSDate new],
                            nextFullIntersectionDate);
                
                [self.keyValueStore setDate:nextFullIntersectionDate
                                        key:OWSContactsManagerKeyNextFullIntersectionDate
                                transaction:transaction];
            } else {
                NSSet<NSString *> *_Nullable lastKnownContactPhoneNumbers =
                [self.keyValueStore getObjectForKey:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                        transaction:transaction];
                
                // If a user has a "flaky" address book, perhaps a network linked directory that
                // goes in and out of existence, we could get thrashing between what the last
                // known set is, causing us to re-intersect contacts many times within the debounce
                // interval. So while we're doing incremental intersections, we *accumulate*,
                // rather than replace the set of recently intersected contacts.
                if ([lastKnownContactPhoneNumbers isKindOfClass:NSSet.class]) {
                    NSSet<NSString *> *_Nullable accumulatedSet =
                    [lastKnownContactPhoneNumbers setByAddingObjectsFromSet:phoneNumbersForIntersection];
                    
                    // replace last known numbers
                    [self.keyValueStore setObject:accumulatedSet
                                              key:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                      transaction:transaction];
                } else {
                    // replace last known numbers
                    [self.keyValueStore setObject:phoneNumbersForIntersection
                                              key:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                      transaction:transaction];
                }
            }
        });
    });
}

- (void)updateWithContacts:(NSArray<Contact *> *)contacts isUserRequested:(BOOL)isUserRequested
{
    dispatch_async(self.intersectionQueue, ^{
        __block ContactsMaps *contactsMaps;
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            NSString *_Nullable localNumber = [self.tsAccountManager localNumberWithTransaction:transaction];
            contactsMaps = [ContactsMaps buildWithContacts:contacts localNumber:localNumber];
            [self.contactsManagerCache setContactsMaps:contactsMaps localNumber:localNumber transaction:transaction];
        });
        
        if (SSKDebugFlags.internalLogging) {
            OWSLogInfo(@"Updating contacts: %lu, phoneNumberToContactMap: %lu",
                       (unsigned long)contactsMaps.uniqueIdToContactMap.count,
                       (unsigned long)contactsMaps.phoneNumberToContactMap.count);
        }
        
        [self.cnContactCache removeAllObjects];
        
        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:OWSContactsManagerContactsDidChangeNotification
                                                                 object:nil];
        
        [self intersectContacts:contactsMaps.allContacts
                isUserRequested:isUserRequested
                     completion:^(NSError *_Nullable error) {
            if (error != nil) {
                OWSFailDebug(@"Error: %@", error);
                return;
            }
            [self buildSignalAccountsAndUpdatePersistedStateForFetchedSystemContacts:contactsMaps.allContacts];
        }];
    });
}

- (nullable NSPersonNameComponents *)cachedContactNameComponentsForAddress:(SignalServiceAddress *)address
                                                               transaction:(SDSAnyReadTransaction *)transaction
{
    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address transaction:transaction];
    NSString *_Nullable phoneNumber = nil;
    if (signalAccount == nil) {
        // We only need the phone number if signalAccount is nil.
        phoneNumber = [self phoneNumberForAddress:address transaction:transaction];
    }
    
    return [self cachedContactNameComponentsForSignalAccount:signalAccount
                                                 phoneNumber:phoneNumber
                                                 transaction:transaction];
}

- (nullable NSPersonNameComponents *)cachedContactNameComponentsForSignalAccount:(nullable SignalAccount *)signalAccount
                                                                     phoneNumber:(nullable NSString *)phoneNumber
                                                                     transaction:(SDSAnyReadTransaction *)transaction
{
    if (!signalAccount) {
        // search system contacts for no-longer-registered signal users, for which there will be no SignalAccount
        Contact *_Nullable nonSignalContact = [self.contactsManagerCache contactForPhoneNumber:phoneNumber
                                                                                   transaction:transaction];
        if (!nonSignalContact) {
            return nil;
        }
        NSPersonNameComponents *nameComponents = [NSPersonNameComponents new];
        nameComponents.givenName = nonSignalContact.firstName;
        nameComponents.familyName = nonSignalContact.lastName;
        nameComponents.nickname = nonSignalContact.nickname;
        return nameComponents;
    }
    
    return signalAccount.contactPersonNameComponents;
}

- (nullable NSString *)phoneNumberForAddress:(SignalServiceAddress *)address
{
    if (address.phoneNumber != nil) {
        return address.phoneNumber;
    }
    
    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address];
    return signalAccount.recipientPhoneNumber;
}

- (nullable NSString *)phoneNumberForAddress:(SignalServiceAddress *)address
                                 transaction:(SDSAnyReadTransaction *)transaction
{
    if (address.phoneNumber != nil) {
        return [address.phoneNumber filterStringForDisplay];
    }
    
    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address transaction:transaction];
    return [signalAccount.recipientPhoneNumber filterStringForDisplay];
}

#pragma mark - View Helpers

- (BOOL)phoneNumber:(PhoneNumber *)phoneNumber1 matchesNumber:(PhoneNumber *)phoneNumber2
{
    return [phoneNumber1.toE164 isEqualToString:phoneNumber2.toE164];
}

#pragma mark - Whisper User Management

- (BOOL)isSystemContactWithPhoneNumberWithSneakyTransaction:(NSString *)phoneNumber
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self isSystemContactWithPhoneNumber:phoneNumber transaction:transaction];
    }];
    return result;
}

- (BOOL)isSystemContactWithPhoneNumber:(NSString *)phoneNumber
                           transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(phoneNumber.length > 0);
    
    return [self.contactsManagerCache contactForPhoneNumber:phoneNumber
                                                transaction:transaction] != nil;
}

- (BOOL)isSystemContactWithAddressWithSneakyTransaction:(SignalServiceAddress *)address
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self isSystemContactWithAddress:address transaction:transaction];
    }];
    return result;
}

- (BOOL)isSystemContactWithAddress:(SignalServiceAddress *)address
                       transaction:(SDSAnyReadTransaction *)transaction
{
    NSString *_Nullable phoneNumber = address.phoneNumber;
    if (phoneNumber.length == 0) {
        return NO;
    }
    return [self isSystemContactWithPhoneNumber:phoneNumber transaction:transaction];
}

- (BOOL)isSystemContactWithSignalAccount:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);
    
    return [self hasSignalAccountForAddress:address];
}

- (BOOL)isSystemContactWithSignalAccount:(SignalServiceAddress *)address
                             transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    
    return [self hasSignalAccountForAddress:address transaction:transaction];
}

- (BOOL)hasNameInSystemContactsForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction
{
    return [self cachedContactNameForAddress:address transaction:transaction].length > 0;
}

- (NSString *)displayNameForThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    if (thread.isNoteToSelf) {
        return MessageStrings.noteToSelf;
    } else if ([thread isKindOfClass:TSContactThread.class]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        return [self displayNameForAddress:contactThread.contactAddress transaction:transaction];
    } else if ([thread isKindOfClass:TSGroupThread.class]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        return groupThread.groupNameOrDefault;
    } else {
        OWSFailDebug(@"unexpected thread: %@", thread);
        return @"";
    }
}

- (NSString *)displayNameForThreadWithSneakyTransaction:(TSThread *)thread
{
    if (thread.isNoteToSelf) {
        return MessageStrings.noteToSelf;
    } else if ([thread isKindOfClass:TSContactThread.class]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        __block NSString *name;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            name = [self displayNameForAddress:contactThread.contactAddress transaction:transaction];
        }];
        return name;
    } else if ([thread isKindOfClass:TSGroupThread.class]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        return groupThread.groupNameOrDefault;
    } else {
        OWSFailDebug(@"unexpected thread: %@", thread);
        return @"";
    }
}

- (NSString *)unknownContactName
{
    return OWSLocalizedString(
                             @"UNKNOWN_CONTACT_NAME", @"Displayed if for some reason we can't determine a contacts phone number *or* name");
}

- (nullable NSString *)nameFromSystemContactsForAddress:(SignalServiceAddress *)address
                                            transaction:(SDSAnyReadTransaction *)transaction
{
    return [self cachedContactNameForAddress:address transaction:transaction];
}

- (NSArray<NSString *> *)displayNamesForAddresses:(NSArray<SignalServiceAddress *> *)addresses
                                      transaction:(SDSAnyReadTransaction *)transaction
{
    return [self objc_displayNamesForAddresses:addresses transaction:transaction];
}

- (NSString *)displayNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    
    // Prefer a saved name from system contacts, if available.
    //
    // We don't need to filterStringForDisplay(); this value is filtered within phoneNumberForAddress,
    // Contact or SignalAccount.
    NSString *_Nullable savedContactName = [self cachedContactNameForAddress:address transaction:transaction];
    if (savedContactName.length > 0) {
        return savedContactName;
    }
    
    // We don't need to filterStringForDisplay(); this value is filtered within OWSUserProfile.
    NSString *_Nullable profileName = [self.profileManager fullNameForAddress:address transaction:transaction];
    // Include the profile name, if set.
    if (profileName.length > 0) {
        return profileName;
    }
    
    // We don't need to filterStringForDisplay(); this value is filtered within phoneNumberForAddress.
    NSString *_Nullable phoneNumber = [self phoneNumberForAddress:address transaction:transaction];
    if (phoneNumber.length > 0) {
        phoneNumber = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:phoneNumber];
        if (phoneNumber.length > 0) {
            return phoneNumber;
        }
    }
    
    // We don't need to filterStringForDisplay(); usernames are strictly filtered.
    NSString *_Nullable username = [self.profileManagerImpl usernameForAddress:address transaction:transaction];
    if (username.length > 0) {
        username = [CommonFormats formatUsername:username];
        return username;
    }
    
    [self fetchProfileForUnknownAddress:address];
    
    return self.unknownUserLabel;
}

// TODO: Remove?
- (NSString *)displayNameForAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);
    
    __block NSString *displayName;
    
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        displayName = [self displayNameForAddress:address transaction:transaction];
    }];
    
    return displayName;
}

- (NSString *)unknownUserLabel
{
    return OWSLocalizedString(@"UNKNOWN_USER", @"Label indicating an unknown user.");
}

- (NSString *)shortDisplayNameForAddress:(SignalServiceAddress *)address
                             transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    
    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address transaction:transaction];
    if (signalAccount != nil) {
        NSString *_Nullable nickname = signalAccount.contactNicknameIfAvailable;
        if (nickname.length > 0) {
            return nickname;
        }
    }
    
    NSPersonNameComponents *_Nullable nameComponents = [self nameComponentsForAddress:address transaction:transaction];
    if (!nameComponents) {
        return [self displayNameForAddress:address transaction:transaction];
    }
    
    return [OWSFormat formatNameComponentsShort:nameComponents];
}

- (nullable NSPersonNameComponents *)nameComponentsForAddress:(SignalServiceAddress *)address
                                                  transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    
    NSPersonNameComponents *_Nullable savedContactNameComponents =
    [self cachedContactNameComponentsForAddress:address transaction:transaction];
    if (savedContactNameComponents) {
        return savedContactNameComponents;
    }

    return [self.profileManager nameComponentsForProfileWithAddress:address transaction:transaction];
}

// TODO: Remove?
- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address);
    
    __block SignalAccount *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.modelReadCaches.signalAccountReadCache getSignalAccountWithAddress:address
                                                                              transaction:transaction];
    }];
    return result;
}

- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address
                                             transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address);
    OWSAssertDebug(transaction);
    
    return [self.modelReadCaches.signalAccountReadCache getSignalAccountWithAddress:address transaction:transaction];
}

- (SignalAccount *)fetchOrBuildSignalAccountForAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address);
    
    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address];
    return (signalAccount ?: [[SignalAccount alloc] initWithSignalServiceAddress:address]);
}

- (BOOL)hasSignalAccountForAddress:(SignalServiceAddress *)address
{
    return [self fetchSignalAccountForAddress:address] != nil;
}

- (BOOL)hasSignalAccountForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    return [self fetchSignalAccountForAddress:address transaction:transaction] != nil;
}

// TODO: Remove?
- (nullable NSData *)profileImageDataForAddressWithSneakyTransaction:(nullable SignalServiceAddress *)address
{
    if (address == nil) {
        OWSFailDebug(@"address was unexpectedly nil");
        return nil;
    }
    
    __block NSData *_Nullable data;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        data = [self.profileManager profileAvatarDataForAddress:address transaction:transaction];
    }];
    return data;
}

- (BOOL)shouldSortByGivenName
{
    return [[CNContactsUserDefaults sharedDefaults] sortOrder] == CNContactSortOrderGivenName;
}

- (NSString *)comparableNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address transaction:transaction];
    if (!signalAccount) {
        signalAccount = [[SignalAccount alloc] initWithSignalServiceAddress:address];
    }
    
    return [self comparableNameForSignalAccount:signalAccount transaction:transaction];
}

- (NSString *)comparableNameForContact:(Contact *)contact
{
    if (self.shouldSortByGivenName) {
        return contact.comparableNameFirstLast;
    }
    
    return contact.comparableNameLastFirst;
}

- (NSString *)comparableNameForSignalAccount:(SignalAccount *)signalAccount
                                 transaction:(SDSAnyReadTransaction *)transaction
{
    {
        Contact *_Nullable contact = signalAccount.contact;
        if (contact != nil) {
            NSString *_Nullable name = [self comparableNameForContact:contact];
            if (name.length > 0) {
                return name;
            }
        }
    }

    NSString *_Nullable phoneNumber = signalAccount.recipientPhoneNumber;
    if (phoneNumber != nil) {
        Contact *_Nullable contact = [self contactForPhoneNumber:phoneNumber transaction:transaction];
        if (contact != nil) {
            NSString *_Nullable name = [self comparableNameForContact:contact];
            if (name.length > 0) {
                return name;
            }
        }
    }
    
    NSPersonNameComponents *_Nullable nameComponents = [self nameComponentsForAddress:signalAccount.recipientAddress
                                                                          transaction:transaction];
    
    if (nameComponents != nil && nameComponents.givenName.length > 0 && nameComponents.familyName.length > 0) {
        NSString *leftName = self.shouldSortByGivenName ? nameComponents.givenName : nameComponents.familyName;
        NSString *rightName = self.shouldSortByGivenName ? nameComponents.familyName : nameComponents.givenName;
        return [NSString stringWithFormat:@"%@\t%@", leftName, rightName];
    }
    
    // Fall back to non-contact display name.
    return [self displayNameForAddress:signalAccount.recipientAddress transaction:transaction];
}

- (nullable ModelReadCacheSizeLease *)leaseCacheSize:(NSInteger)size {
    return [self.modelReadCaches.signalAccountReadCache leaseCacheSize:size];
}

@end

NS_ASSUME_NONNULL_END
