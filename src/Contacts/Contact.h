#import <AddressBook/AddressBook.h>
#import <Foundation/Foundation.h>

/**
 *
 * Contact represents relevant information related to a contact from the user's
 * contact list.
 *
 */

@interface Contact : NSObject

@property (readonly, nonatomic) NSString *firstName;
@property (readonly, nonatomic) NSString *lastName;
@property (readonly, nonatomic) NSArray *parsedPhoneNumbers;
@property (readonly, nonatomic) NSArray *userTextPhoneNumbers;
@property (readonly, nonatomic) NSArray *emails;
@property (readonly, nonatomic) NSString *notes;

- (NSString *)fullName;
- (NSString *)allPhoneNumbers;

- (BOOL)isTextSecureContact;
- (BOOL)isRedPhoneContact;

- (NSArray *)textSecureIdentifiers;
- (NSArray *)redPhoneIdentifiers;

#if TARGET_OS_IOS

- (instancetype)initWithContactWithFirstName:(NSString *)firstName
                                 andLastName:(NSString *)lastName
                     andUserTextPhoneNumbers:(NSArray *)phoneNumbers
                                andContactID:(ABRecordID)record;

@property (readonly, nonatomic) UIImage *image;
@property (readonly, nonatomic) ABRecordID recordID;
#endif

@end
