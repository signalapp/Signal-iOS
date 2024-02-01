//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSContactsManager.h"
#import "OWSProfileManager.h"
#import <Contacts/Contacts.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const OWSContactsManagerSignalAccountsDidChangeNotification
= @"OWSContactsManagerSignalAccountsDidChangeNotification";
NSNotificationName const OWSContactsManagerContactsDidChangeNotification
= @"OWSContactsManagerContactsDidChangeNotification";

NSString *const OWSContactsManagerCollection = @"OWSContactsManagerCollection";

@interface OWSContactsManager () <SystemContactsFetcherDelegate>

@property (nonatomic) BOOL isContactsUpdateInFlight;

@property (nonatomic, readonly) SystemContactsFetcher *systemContactsFetcher;
@property (atomic) BOOL isSetup;

@end

#pragma mark -

@implementation OWSContactsManager

- (id)initWithSwiftValues:(OWSContactsManagerSwiftValues *)swiftValues
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
    _swiftValues = swiftValues;

    OWSSingletonAssert();
    
    AppReadinessRunNowOrWhenAppWillBecomeReady(^{
        [self setup];
    });
    
    return self;
}

- (void)setup {
    [self setUpSystemContacts];
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
    return [TSAccountManagerObjcBridge isPrimaryDeviceWithMaybeTransaction];
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
    [self updateContacts:contacts isUserRequested:isUserRequested];
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
            [self updateContacts:nil isUserRequested:NO];
        case RawContactAuthorizationStatusNotDetermined:
        case RawContactAuthorizationStatusAuthorized:
            break;
    }
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
        if (!phoneNumber) {
            return nil;
        }
        // search system contacts for no-longer-registered signal users, for which there will be no SignalAccount
        Contact *_Nullable nonSignalContact = [self contactForPhoneNumber:phoneNumber transaction:transaction];
        if (!nonSignalContact) {
            return nil;
        }
        NSPersonNameComponents *nameComponents = [NSPersonNameComponents new];
        nameComponents.givenName = nonSignalContact.firstName;
        nameComponents.familyName = nonSignalContact.lastName;
        nameComponents.nickname = nonSignalContact.nickname;
        return nameComponents;
    }

    return [signalAccount contactPersonNameComponentsWithUserDefaults:NSUserDefaults.standardUserDefaults];
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

    return [self contactForPhoneNumber:phoneNumber transaction:transaction] != nil;
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
    return [self displayNamesForAddresses:@[ address ] transaction:transaction].firstObject;
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
        NSString *_Nullable nickname =
            [signalAccount contactNicknameIfAvailableWithUserDefaults:NSUserDefaults.standardUserDefaults];
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

    return [self.profileManagerObjC nameComponentsForProfileWithAddress:address transaction:transaction];
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
        data = [self.profileManagerObjC profileAvatarDataForAddress:address transaction:transaction];
    }];
    return data;
}

- (NSArray<SignalServiceAddress *> *)sortSignalServiceAddressesObjC:(NSArray<SignalServiceAddress *> *)addresses
                                                        transaction:(SDSAnyReadTransaction *)transaction
{
    return [self _sortSignalServiceAddressesObjC:addresses transaction:transaction];
}

- (BOOL)shouldSortByGivenName
{
    return [[CNContactsUserDefaults sharedDefaults] sortOrder] == CNContactSortOrderGivenName;
}

- (NSString *)comparableNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address transaction:transaction];
    if (!signalAccount) {
        signalAccount = [[SignalAccount alloc] initWithContact:nil address:address];
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
