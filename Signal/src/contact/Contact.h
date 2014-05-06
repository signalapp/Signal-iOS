#import <Foundation/Foundation.h>
#import <AddressBook/AddressBook.h>
#import "PhoneNumber.h"

/**
 *
 * Contact represents relevant information related to a contact from the user's contact list.
 *
 */

@interface Contact : NSObject

@property (readonly,nonatomic) NSString* firstName;
@property (readonly,nonatomic) NSString* lastName;
@property (readonly,nonatomic) NSArray* parsedPhoneNumbers;
@property (readonly,nonatomic) NSArray* userTextPhoneNumbers;
@property (readonly,nonatomic) NSArray* emails;
@property (readonly,nonatomic) UIImage* image;
@property (readonly,nonatomic) NSString *notes;
@property (readonly,nonatomic) ABRecordID recordID;
@property (nonatomic, assign) BOOL isFavourite;

+ (Contact*)contactWithFirstName:(NSString*)firstName
                     andLastName:(NSString *)lastName
         andUserTextPhoneNumbers:(NSArray*)phoneNumbers
                       andEmails:(NSArray*)emails
                    andContactID:(ABRecordID)record;

+ (Contact*)contactWithFirstName:(NSString*)firstName
                     andLastName:(NSString *)lastName
         andUserTextPhoneNumbers:(NSArray*)numbers
                       andEmails:(NSArray*)emails
                        andImage:(UIImage *)image
                    andContactID:(ABRecordID)record
                  andIsFavourite:(BOOL)isFavourite
                        andNotes:(NSString *)notes;

- (NSString *)fullName;

@end
