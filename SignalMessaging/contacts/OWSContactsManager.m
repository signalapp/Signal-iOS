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

- (nullable NSString *)systemContactNameForAddress:(SignalServiceAddress *)address
                                       transaction:(SDSAnyReadTransaction *)transaction
{
    return [self _systemContactNameFor:address tx:transaction];
}

- (BOOL)isSystemContactWithPhoneNumber:(NSString *)phoneNumber transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(phoneNumber.length > 0);

    return [self contactForPhoneNumber:phoneNumber transaction:transaction] != nil;
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

- (NSString *)shortDisplayNameForAddress:(SignalServiceAddress *)address
                             transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    NSPersonNameComponents *_Nullable nameComponents = [self nameComponentsForAddress:address transaction:transaction];
    if (nameComponents.nickname.length > 0) {
        return nameComponents.nickname;
    }
    if (!nameComponents) {
        return [self displayNameForAddress:address transaction:transaction];
    }
    
    return [OWSFormat formatNameComponentsShort:nameComponents];
}

- (nullable NSPersonNameComponents *)nameComponentsForAddress:(SignalServiceAddress *)address
                                                  transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    return ({
        SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address transaction:transaction];
        [signalAccount contactPersonNameComponentsWithUserDefaults:NSUserDefaults.standardUserDefaults];
    })
        ?: ({ [self.profileManagerObjC nameComponentsForProfileWithAddress:address transaction:transaction]; });
}

- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address
                                             transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address);
    OWSAssertDebug(transaction);
    
    return [self.modelReadCaches.signalAccountReadCache getSignalAccountWithAddress:address transaction:transaction];
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
    NSPersonNameComponents *_Nullable nameComponents = [self nameComponentsForAddress:address transaction:transaction];

    if (nameComponents != nil && nameComponents.givenName.length > 0 && nameComponents.familyName.length > 0) {
        NSString *leftName = self.shouldSortByGivenName ? nameComponents.givenName : nameComponents.familyName;
        NSString *rightName = self.shouldSortByGivenName ? nameComponents.familyName : nameComponents.givenName;
        return [NSString stringWithFormat:@"%@\t%@", leftName, rightName];
    }

    // Fall back to non-system contact, non-profile display name.
    return [self displayNameForAddress:address transaction:transaction];
}

- (nullable ModelReadCacheSizeLease *)leaseCacheSize:(NSInteger)size {
    return [self.modelReadCaches.signalAccountReadCache leaseCacheSize:size];
}

@end

NS_ASSUME_NONNULL_END
