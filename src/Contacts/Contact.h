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


- (BOOL)isSignalContact;
- (NSArray<NSString *> *)textSecureIdentifiers;

#if TARGET_OS_IOS

- (instancetype)initWithContactWithFirstName:(NSString *)firstName
                                 andLastName:(NSString *)lastName
                     andUserTextPhoneNumbers:(NSArray *)phoneNumbers
                                    andImage:(UIImage *)image
                                andContactID:(ABRecordID)record;

@property (readonly, nonatomic) UIImage *image;
@property (readonly, nonatomic) ABRecordID recordID;
#endif

@end
