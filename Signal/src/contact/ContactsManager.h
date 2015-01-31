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
@private ObservableValueController* observableRedPhoneUsersController;
@private ObservableValueController* observableTextSecureUsersController;
@private TOCCancelTokenSource* life;
@private NSDictionary *latestContactsById;
@private NSDictionary *latestWhisperUsersById;
}

-(ObservableValue *) getObservableContacts;
-(ObservableValue *) getObservableRedPhoneUsers;

- (BOOL)isPhoneNumberRegisteredWithRedPhone:(PhoneNumber*)phoneNumber;

-(NSArray*) getContactsFromAddressBook:(ABAddressBookRef)addressBook;
-(Contact*) latestContactWithRecordId:(ABRecordID)recordId;
-(Contact*) latestContactForPhoneNumber:(PhoneNumber *)phoneNumber;
-(NSArray*) latestContactsWithSearchString:(NSString *)searchString;

+(NSDictionary *)groupContactsByFirstLetter:(NSArray *)contacts matchingSearchString:(NSString *)optionalSearchString;

+(BOOL)name:(NSString *)nameString matchesQuery:(NSString *)queryString;
+(BOOL)phoneNumber:(PhoneNumber *)phoneNumber matchesQuery:(NSString *)queryString;

- (NSArray*)allContacts;
- (NSArray*)signalContacts;
- (NSArray*)textSecureContacts;

- (BOOL)isContactRegisteredWithRedPhone:(Contact*)contact;

-(void)doAfterEnvironmentInitSetup;

- (NSString*)nameStringForPhoneIdentifier:(NSString*)identifier;
- (UIImage*)imageForPhoneIdentifier:(NSString*)identifier;

@end
