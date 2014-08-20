#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "Contact.h"
#import "ObservableValue.h"

/**
 *
 * ContactsManager provides access to an updated list of contacts with optional categorizations -
 * such as searching and favourite-attributed contacts (favourites are also managed through this class)
 * Others can subscribe for contact and/or favourite updates
 * Contacts can be grouped by first letter into an NSDictionary in order to display in individual sections-
 * in the ContactBrowseViewController.
 *
 */

typedef void(^ABAccessRequestCompletionBlock)(BOOL hasAccess);
typedef void(^ABReloadRequestCompletionBlock)(NSArray *contacts);

@interface ContactsManager : NSObject {
@private TOCFuture* futureAddressBook;
@private ObservableValueController* observableContactsController;
@private ObservableValueController* observableWhisperUsersController;
@private ObservableValueController* observableFavouritesController;
@private TOCCancelTokenSource* life;
@private NSDictionary *latestContactsById;
@private NSDictionary *latestWhisperUsersById;
}

-(ObservableValue *) getObservableContacts;
-(ObservableValue *) getObservableWhisperUsers;
-(ObservableValue *) getObservableFavourites;

-(NSArray*) getContactsFromAddressBook:(ABAddressBookRef)addressBook;
-(Contact*) latestContactWithRecordId:(ABRecordID)recordId;
-(Contact*) latestContactForPhoneNumber:(PhoneNumber *)phoneNumber;
-(NSArray*) latestContactsWithSearchString:(NSString *)searchString;

-(void) toggleFavourite:(Contact *)contact;
-(NSArray*) contactsForContactIds:(NSArray *)favouriteIds;
+(NSArray *)favouritesForAllContacts:(NSArray *)contacts;

-(void) addContactsToKnownWhisperUsers:(NSArray*) contacts;

+(NSDictionary *)groupContactsByFirstLetter:(NSArray *)contacts matchingSearchString:(NSString *)optionalSearchString;

+(BOOL)name:(NSString *)nameString matchesQuery:(NSString *)queryString;
+(BOOL)phoneNumber:(PhoneNumber *)phoneNumber matchesQuery:(NSString *)queryString;
-(BOOL)isContactRegisteredWithWhisper:(Contact*) contact;

-(void) doAfterEnvironmentInitSetup;

-(void) enableNewUserNotifications;
-(NSUInteger) getNumberOfUnacknowledgedCurrentUsers;


@end
