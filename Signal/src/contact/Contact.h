#import <Foundation/Foundation.h>
#import <AddressBook/AddressBook.h>
#import "PhoneNumber.h"

/**
 *
 * Contact represents relevant information related to a contact from the user's contact list.
 *
 */

@interface Contact : NSObject

@property (nonatomic, readonly) NSString* firstName;
@property (nonatomic, readonly) NSString* lastName;
@property (nonatomic, readonly) NSString* fullName;
@property (nonatomic, readonly) NSArray* parsedPhoneNumbers;
@property (nonatomic, readonly) NSArray* userTextPhoneNumbers;
@property (nonatomic, readonly) NSArray* emails;
@property (nonatomic, readonly) UIImage* image;
@property (nonatomic, readonly) NSString* notes;
@property (nonatomic, readonly) ABRecordID recordID;
@property (nonatomic) BOOL isFavourite;

- (instancetype)initWithFirstName:(NSString*)firstName
                      andLastName:(NSString*)lastName
          andUserTextPhoneNumbers:(NSArray*)phoneNumbers
                        andEmails:(NSArray*)emails
                     andContactID:(ABRecordID)record;

- (instancetype)initWithFirstName:(NSString*)firstName
                      andLastName:(NSString*)lastName
          andUserTextPhoneNumbers:(NSArray*)numbers
                        andEmails:(NSArray*)emails
                         andImage:(UIImage*)image
                     andContactID:(ABRecordID)record
                   andIsFavourite:(BOOL)isFavourite
                         andNotes:(NSString*)notes;

@end
