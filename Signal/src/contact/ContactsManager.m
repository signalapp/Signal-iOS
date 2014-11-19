#import "ContactsManager.h"
#import <AddressBook/AddressBook.h>
#import <libPhoneNumber-iOS/NBPhoneNumber.h>
#import "Environment.h"
#import "NotificationManifest.h"
#import "PhoneNumberDirectoryFilter.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "PropertyListPreferences+Util.h"
#import "Util.h"

#define ADDRESSBOOK_QUEUE dispatch_get_main_queue()

static NSString* const FAVOURITES_DEFAULT_KEY = @"FAVOURITES_DEFAULT_KEY";
static NSString* const KNOWN_USERS_DEFAULT_KEY = @"KNOWN_USERS_DEFAULT_KEY";

typedef BOOL (^ContactSearchBlock)(id, NSUInteger, BOOL*);

@interface ContactsManager ()

@property (strong, nonatomic) TOCFuture* futureAddressBook;
@property (strong, nonatomic) ObservableValueController* observableContactsController;
@property (strong, nonatomic) ObservableValueController* observableWhisperUsersController;
@property (strong, nonatomic) ObservableValueController* observableFavouritesController;
@property (strong, nonatomic) TOCCancelTokenSource* life;
@property (strong, nonatomic) NSDictionary* latestContactsById;
@property (strong, nonatomic) NSDictionary* latestWhisperUsersById;
@property (strong, nonatomic) NSMutableArray* favouriteContactIds;
@property (strong, nonatomic) NSMutableArray* knownWhisperUserIds;
@property (nonatomic) BOOL newUserNotificationsEnabled;

@property (strong, nonatomic) id addressBookReference;

@end

@implementation ContactsManager

- (instancetype)init {
    if (self = [super init]) {
        self.newUserNotificationsEnabled = [self knownUserStoreInitialized];
        self.favouriteContactIds = [self loadFavouriteIds];
        self.knownWhisperUserIds = [self loadKnownWhisperUsers];
        self.life = [[TOCCancelTokenSource alloc] init];
        self.observableContactsController = [[ObservableValueController alloc] initWithInitialValue:nil];
        self.observableWhisperUsersController = [[ObservableValueController alloc] initWithInitialValue:nil];
        [self registerNotificationHandlers];
    }
    
    return self;
}

- (void)doAfterEnvironmentInitSetup {
    [self setupAddressBook];
    [self.observableContactsController watchLatestValueOnArbitraryThread:^(NSArray *latestContacts) {
        @synchronized(self) {
            [self setupLatestContacts:latestContacts];
        }
    } untilCancelled:self.life.token];
    
    [self.observableWhisperUsersController watchLatestValueOnArbitraryThread:^(NSArray *latestUsers) {
        @synchronized(self) {
            [self setupLatestWhisperUsers:latestUsers];
        }
    } untilCancelled:self.life.token];
}

- (void)dealloc {
    [self.life cancel];
}

#pragma mark - Notification Handlers
- (void)registerNotificationHandlers{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updatedDirectoryHandler:)
                                                 name:NOTIFICATION_DIRECTORY_UPDATE
                                               object:nil];
}

- (void)updatedDirectoryHandler:(NSNotification*)notification {
    [self checkForNewWhisperUsers];
}

- (void)enableNewUserNotifications{
    self.newUserNotificationsEnabled = YES;
}

#pragma mark - Address Book callbacks

void onAddressBookChanged(ABAddressBookRef notifyAddressBook, CFDictionaryRef info, void *context);
void onAddressBookChanged(ABAddressBookRef notifyAddressBook, CFDictionaryRef info, void *context) {
    ContactsManager* contactsManager = (__bridge ContactsManager*)context;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [contactsManager pullLatestAddressBook];
        
    });
}

#pragma mark - Setup

- (void)setupAddressBook {
    dispatch_async(ADDRESSBOOK_QUEUE, ^{
        [[ContactsManager asyncGetAddressBook] thenDo:^(id addressBook) {
            self.addressBookReference = addressBook;
            ABAddressBookRef cfAddressBook = (__bridge ABAddressBookRef)addressBook;
            ABAddressBookRegisterExternalChangeCallback(cfAddressBook, onAddressBookChanged, (__bridge void*)self);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
                [self pullLatestAddressBook];
            });
        }];
    });
}

- (void)pullLatestAddressBook{
    CFErrorRef creationError = nil;
    ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, &creationError);
    checkOperationDescribe(nil == creationError, [((__bridge NSError*)creationError) localizedDescription]) ;
    ABAddressBookRequestAccessWithCompletion(addressBookRef,  nil);
    [self.observableContactsController updateValue:[self getContactsFromAddressBook:addressBookRef]];
}

- (void)setupLatestContacts:(NSArray*)contacts {
    if (contacts) {
        self.latestContactsById = [ContactsManager keyContactsById:contacts];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [self checkForNewWhisperUsers];
        });
    }
}

- (void)setupLatestWhisperUsers:(NSArray*)users {
    if (users) {
        self.latestWhisperUsersById = [ContactsManager keyContactsById:users];
        
        if (!self.observableFavouritesController) {
            NSArray *favourites = [self contactsForContactIds:self.favouriteContactIds];
            self.observableFavouritesController = [[ObservableValueController alloc] initWithInitialValue:favourites];
        }

    }
}

#pragma mark - Observables

- (ObservableValue*)getObservableContacts {
    return self.observableContactsController;
}

- (ObservableValue*)getObservableWhisperUsers {
    return self.observableWhisperUsersController;
}

- (ObservableValue*)getObservableFavourites {
    return self.observableFavouritesController;
}

#pragma mark - Address Book utils

+ (TOCFuture*)asyncGetAddressBook {
    CFErrorRef creationError = nil;
    ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, &creationError);
    assert((addressBookRef == nil) == (creationError != nil));
    if (creationError != nil) {
        return [TOCFuture futureWithFailure:(__bridge_transfer id)creationError];
    }

    TOCFutureSource* futureAddressBookSource = [[TOCFutureSource alloc] init];

    id addressBook = (__bridge_transfer id)addressBookRef;
    ABAddressBookRequestAccessWithCompletion(addressBookRef, ^(bool granted, CFErrorRef requestAccessError) {
        if (granted) {
            dispatch_async(ADDRESSBOOK_QUEUE,^{
                [futureAddressBookSource trySetResult:addressBook];
            });
        } else {
            [futureAddressBookSource trySetFailure:(__bridge id)requestAccessError];
        }
    });

    return futureAddressBookSource.future;
}

- (NSArray*)getContactsFromAddressBook:(ABAddressBookRef)addressBook {
    CFArrayRef allPeople = ABAddressBookCopyArrayOfAllPeople(addressBook);
    CFMutableArrayRef allPeopleMutable = CFArrayCreateMutableCopy(kCFAllocatorDefault,
                                                                  CFArrayGetCount(allPeople),allPeople);
    
    CFArraySortValues(allPeopleMutable,CFRangeMake(0, CFArrayGetCount(allPeopleMutable)),
                      (CFComparatorFunction)ABPersonComparePeopleByName,
                      (void*)(unsigned long)ABPersonGetSortOrdering());
    
    NSArray* sortedPeople = (__bridge_transfer NSArray*)allPeopleMutable;

    // This predicate returns all contacts from the addressbook having at least one phone number
    
    NSPredicate* predicate = [NSPredicate predicateWithBlock: ^BOOL(id record, NSDictionary* bindings) {
        ABMultiValueRef phoneNumbers = ABRecordCopyValue( (__bridge ABRecordRef)record, kABPersonPhoneProperty);
        BOOL result = NO;
        
        for (CFIndex i = 0; i < ABMultiValueGetCount(phoneNumbers); i++) {
            NSString* phoneNumber = (__bridge_transfer NSString*)ABMultiValueCopyValueAtIndex(phoneNumbers, i);
            if (phoneNumber.length>0) {
                result = YES;
                break;
            }
        }
        CFRelease(phoneNumbers);
        return result;
    }];
    CFRelease(allPeople);
    NSArray* filteredContacts = [sortedPeople filteredArrayUsingPredicate:predicate];
    
    return [filteredContacts map:^id(id item) {
        return [self contactForRecord:(__bridge ABRecordRef)item];
    }];
}

- (NSArray*)latestContactsWithSearchString:(NSString*)searchString {
    return [self.latestContactsById.allValues filter:^int(Contact* contact) {
        return searchString.length == 0 || [ContactsManager name:contact.fullName matchesQuery:searchString];
    }];
}

#pragma mark - Contact/Phone Number util

- (Contact*)contactForRecord:(ABRecordRef)record {
    ABRecordID recordID = ABRecordGetRecordID(record);

    NSString* firstName = (__bridge_transfer NSString*)ABRecordCopyValue(record, kABPersonFirstNameProperty);
    NSString* lastName = (__bridge_transfer NSString*)ABRecordCopyValue(record, kABPersonLastNameProperty);
    NSArray* phoneNumbers = [self phoneNumbersForRecord:record];

    if (!firstName && !lastName) {
        NSString* companyName = (__bridge_transfer NSString*)ABRecordCopyValue(record, kABPersonOrganizationProperty);
        if (companyName) {
            firstName = companyName;
        } else if (phoneNumbers.count) {
            firstName =	phoneNumbers.firstObject;
        }
    }

    NSString* notes = (__bridge_transfer NSString*)ABRecordCopyValue(record, kABPersonNoteProperty);
    NSArray* emails = [ContactsManager emailsForRecord:record];
    NSData* image = (__bridge_transfer NSData*)ABPersonCopyImageDataWithFormat(record, kABPersonImageFormatThumbnail);
    UIImage* img = [UIImage imageWithData:image];
        
    ContactSearchBlock searchBlock = ^BOOL(NSNumber* obj, NSUInteger idx, BOOL* stop) {
        return [obj intValue] == recordID;
    };

    NSUInteger favouriteIndex = [self.favouriteContactIds indexOfObjectPassingTest:searchBlock];

    return [[Contact alloc] initWithFirstName:firstName
                                  andLastName:lastName
                      andUserTextPhoneNumbers:phoneNumbers
                                    andEmails:emails
                                     andImage:img
                                 andContactID:recordID
                               andIsFavourite:favouriteIndex != NSNotFound
                                     andNotes:notes];
}

- (Contact*)latestContactForPhoneNumber:(PhoneNumber*)phoneNumber {
    NSArray* allContacts = self.latestContactsById.allValues;

    ContactSearchBlock searchBlock = ^BOOL(Contact* contact, NSUInteger idx, BOOL* stop) {
        for (PhoneNumber* number in contact.parsedPhoneNumbers) {
            
            if ([self phoneNumber:number matchesNumber:phoneNumber]) {
                *stop = YES;
                return YES;
            }
        }
        return NO;
    };

    NSUInteger contactIndex = [allContacts indexOfObjectPassingTest:searchBlock];

    if (contactIndex != NSNotFound) {
        return allContacts[contactIndex];
    } else {
        return nil;
    }
}

- (BOOL)phoneNumber:(PhoneNumber*)phoneNumber1 matchesNumber:(PhoneNumber*)phoneNumber2 {
    return [phoneNumber1.toE164 isEqualToString:phoneNumber2.toE164];
}

- (NSArray*)phoneNumbersForRecord:(ABRecordRef)record {
    ABMultiValueRef numberRefs = ABRecordCopyValue(record, kABPersonPhoneProperty);

    @try {
        NSArray* phoneNumbers = (__bridge_transfer NSArray*)ABMultiValueCopyArrayOfAllValues(numberRefs);
        
        if (phoneNumbers == nil) phoneNumbers = @[];
        
        NSMutableArray* numbers = [[NSMutableArray alloc] init];
        
        for (NSUInteger i = 0; i < phoneNumbers.count; i++) {
            NSString* phoneNumber = phoneNumbers[i];
            [numbers addObject:phoneNumber];
        }
        
        return numbers;
        
    } @finally {
        if (numberRefs) {
            CFRelease(numberRefs);
        }
    }
}

+ (NSArray*)emailsForRecord:(ABRecordRef)record {
    ABMultiValueRef emailRefs = ABRecordCopyValue(record, kABPersonEmailProperty);

    @try {
        NSArray *emails = (__bridge_transfer NSArray*)ABMultiValueCopyArrayOfAllValues(emailRefs);
        
        if (emails == nil) emails = @[];
        
        return emails;
        
    } @finally {
        if (emailRefs) {
            CFRelease(emailRefs);
        }
    }
}

+ (NSDictionary*)groupContactsByFirstLetter:(NSArray*)contacts
                       matchingSearchString:(NSString*)optionalSearchString {
    require(contacts != nil);

    NSArray* matchingContacts = [contacts filter:^int(Contact* contact) {
        return optionalSearchString.length == 0 || [self name:contact.fullName matchesQuery:optionalSearchString];
    }];

    return [matchingContacts groupBy:^id(Contact* contact) {
        NSString* nameToUse = @"";
    
        BOOL firstNameOrdering = ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst?YES:NO;
        
        if (firstNameOrdering && contact.firstName != nil && contact.firstName.length > 0) {
            nameToUse = contact.firstName;
        } else if (!firstNameOrdering && contact.lastName != nil && contact.lastName.length > 0){
            nameToUse = contact.lastName;
        } else if (contact.lastName == nil) {
            if (contact.fullName.length > 0) {
                nameToUse = contact.fullName;
            } else {
                return nameToUse;
            }
        } else {
            nameToUse = contact.lastName;
        }
        
        if (nameToUse.length >= 1) {
            return [[[nameToUse substringToIndex:1] uppercaseString] decomposedStringWithCompatibilityMapping];
        } else {
            return @" ";
        }
    }];
}

+ (NSDictionary*)keyContactsById:(NSArray*)contacts {
    return [contacts keyedBy:^id(Contact *contact) {
        return @((int)contact.recordID);
    }];
}

- (Contact*)latestContactWithRecordId:(ABRecordID)recordId {
    @synchronized(self) {
        return self.latestContactsById[@(recordId)];
    }
}

- (NSArray*)recordsForContacts:(NSArray*)contacts {
    return [contacts map:^id(Contact* contact) {
        return @([contact recordID]);
    }];
}

+ (BOOL)name:(NSString*)nameString matchesQuery:(NSString*)queryString {
    NSCharacterSet* whitespaceSet = NSCharacterSet.whitespaceCharacterSet;
    NSArray* queryStrings = [queryString componentsSeparatedByCharactersInSet:whitespaceSet];
    NSArray* nameStrings = [nameString componentsSeparatedByCharactersInSet:whitespaceSet];

    return [queryStrings all:^int(NSString* query) {
        if (query.length == 0) return YES;
        return [nameStrings any:^int(NSString* nameWord) {
            NSStringCompareOptions searchOpts = NSCaseInsensitiveSearch | NSAnchoredSearch;
            return [nameWord rangeOfString:query options:searchOpts].location != NSNotFound;
        }];
    }];
}

+ (BOOL)phoneNumber:(PhoneNumber*)phoneNumber matchesQuery:(NSString*)queryString {
    NSString* phoneNumberString = phoneNumber.localizedDescriptionForUser;
    NSString* searchString = phoneNumberString.digitsOnly;

    if (queryString.length == 0) return YES;
    NSStringCompareOptions searchOpts = NSCaseInsensitiveSearch | NSAnchoredSearch;
    return [searchString rangeOfString:queryString options:searchOpts].location != NSNotFound;
}

- (NSArray*)contactsForContactIds:(NSArray*)contactIds {
    NSMutableArray* contacts = [[NSMutableArray alloc] init];
    for (NSNumber* favouriteId in contactIds) {
        Contact* contact = [self latestContactWithRecordId:[favouriteId intValue]];
        
        if (contact) {
            [contacts addObject:contact];
        }
    }
    return [contacts copy];
}

#pragma mark - Favourites

- (NSMutableArray*)loadFavouriteIds {
    NSArray* favourites = [NSUserDefaults.standardUserDefaults objectForKey:FAVOURITES_DEFAULT_KEY];
    return favourites == nil ? [NSMutableArray array] : favourites.mutableCopy;
}

- (void)saveFavouriteIds {
    [NSUserDefaults.standardUserDefaults setObject:[self.favouriteContactIds copy]
                                              forKey:FAVOURITES_DEFAULT_KEY];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self.observableFavouritesController updateValue:[self contactsForContactIds:self.favouriteContactIds]];
}

- (void)toggleFavourite:(Contact*)contact {
    require(contact != nil);

    contact.isFavourite = !contact.isFavourite;
    if (contact.isFavourite) {
        [self.favouriteContactIds addObject:@(contact.recordID)];
    } else {
        
        ContactSearchBlock removeBlock = ^BOOL(NSNumber* favouriteNumber, NSUInteger idx, BOOL* stop) {
            return [favouriteNumber integerValue] == contact.recordID;
        };
        
        NSUInteger indexToRemove = [self.favouriteContactIds indexOfObjectPassingTest:removeBlock];
        
        if (indexToRemove != NSNotFound) {
            [self.favouriteContactIds removeObjectAtIndex:indexToRemove];
        }
    }
    [self saveFavouriteIds];
}

+ (NSArray*)favouritesForAllContacts:(NSArray*)contacts {
    return [contacts filter:^int(Contact* contact) {
        return contact.isFavourite;
    }];
}

#pragma mark - Whisper User Management

- (NSUInteger)checkForNewWhisperUsers {
	NSArray* currentUsers = [self getWhisperUsersFromContactsArray:self.latestContactsById.allValues];
	NSArray* newUsers     = [self getNewItemsFrom:currentUsers comparedTo:self.latestWhisperUsersById.allValues];
    
	if(newUsers.count > 0){
		[self.observableWhisperUsersController updateValue:currentUsers];
	}
    
    NSArray* unacknowledgedUserIds = [self getUnacknowledgedUsersFrom:currentUsers];
    if(unacknowledgedUserIds.count > 0) {
        NSArray *unacknowledgedUsers = [self contactsForContactIds: unacknowledgedUserIds];
        if(!self.newUserNotificationsEnabled) {
            [self addContactsToKnownWhisperUsers:unacknowledgedUsers];
        } else {
            NSDictionary* payload = @{NOTIFICATION_DATAKEY_NEW_USERS: unacknowledgedUsers};
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_NEW_USERS_AVAILABLE object:self userInfo:payload];
        }
    }
    return newUsers.count;
}

- (NSArray*)getUnacknowledgedUsersFrom:(NSArray*)users {
    NSArray* userIds = [self recordsForContacts:users];
    return [self getNewItemsFrom:userIds comparedTo:self.knownWhisperUserIds];
}

- (NSUInteger)getNumberOfUnacknowledgedCurrentUsers {
    NSArray* currentUsers = [self getWhisperUsersFromContactsArray:self.latestContactsById.allValues];
    return [[self getUnacknowledgedUsersFrom:currentUsers] count];
}

- (NSArray*)getWhisperUsersFromContactsArray:(NSArray*)contacts {
	return [contacts filter:^int(Contact* contact) {
        return [self isContactRegisteredWithWhisper:contact];
    }];
}

- (NSArray*)getNewItemsFrom:(NSArray*)newArray comparedTo:(NSArray*)oldArray {
	NSMutableSet* newSet = [[NSMutableSet alloc] initWithArray:newArray];
	NSSet *oldSet = [[NSSet alloc] initWithArray:oldArray];
	
	[newSet minusSet:oldSet];
	return newSet.allObjects;
}

- (BOOL)isContactRegisteredWithWhisper:(Contact*)contact {
	for (PhoneNumber* phoneNumber in contact.parsedPhoneNumbers){
		if ([self isPhoneNumberRegisteredWithWhisper:phoneNumber]) {
			return YES;
		}
	}
	return NO;
}

- (BOOL)isPhoneNumberRegisteredWithWhisper:(PhoneNumber*)phoneNumber {
	PhoneNumberDirectoryFilter* directory = Environment.getCurrent.phoneDirectoryManager.getCurrentFilter;
	return phoneNumber != nil && [directory containsPhoneNumber:phoneNumber];
}

- (void)addContactsToKnownWhisperUsers:(NSArray*)contacts {
    for(Contact* contact in contacts){
        [self.knownWhisperUserIds addObject:@([contact recordID])];
    }
    NSMutableSet *users = [[NSMutableSet alloc] initWithArray:self.latestWhisperUsersById.allValues];
    [users addObjectsFromArray:contacts];
    
    [self.observableWhisperUsersController updateValue:users.allObjects];
    [self saveKnownWhisperUsers];
}

- (BOOL)knownUserStoreInitialized {
    NSUserDefaults* d = [NSUserDefaults.standardUserDefaults objectForKey:KNOWN_USERS_DEFAULT_KEY];
    return (Nil != d);
}

- (NSMutableArray*)loadKnownWhisperUsers{
    NSArray* knownUsers = [NSUserDefaults.standardUserDefaults objectForKey:KNOWN_USERS_DEFAULT_KEY];
    return knownUsers == nil ? [[NSMutableArray alloc] init] : knownUsers.mutableCopy;
}

- (void)saveKnownWhisperUsers {
    self.knownWhisperUserIds = [[NSMutableArray alloc] initWithArray:[self.latestWhisperUsersById allKeys]];
    [NSUserDefaults.standardUserDefaults setObject:[self.knownWhisperUserIds copy] forKey:KNOWN_USERS_DEFAULT_KEY];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (void)clearKnownWhisUsers{
    [NSUserDefaults.standardUserDefaults setObject:@[] forKey:KNOWN_USERS_DEFAULT_KEY];
    [NSUserDefaults.standardUserDefaults synchronize];
}

@end
