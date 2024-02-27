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

- (NSString *)displayNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    return [self displayNamesFor:@[ address ] transaction:transaction].firstObject;
}

- (NSString *)shortDisplayNameForAddress:(SignalServiceAddress *)address
                             transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    NSPersonNameComponents *_Nullable nameComponents = [self nameComponentsFor:address transaction:transaction];
    if (nameComponents.nickname.length > 0) {
        return nameComponents.nickname;
    }
    if (!nameComponents) {
        return [self displayNameForAddress:address transaction:transaction];
    }
    
    return [OWSFormat formatNameComponentsShort:nameComponents];
}

- (NSArray<SignalServiceAddress *> *)sortSignalServiceAddressesObjC:(NSArray<SignalServiceAddress *> *)addresses
                                                        transaction:(SDSAnyReadTransaction *)transaction
{
    return [self _sortSignalServiceAddressesObjC:addresses transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
