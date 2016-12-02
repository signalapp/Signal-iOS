//  Created by Frederic Jacobs on 05/12/15.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

@class PhoneNumber;
@class Contact;
@class UIImage;

@protocol ContactsManagerProtocol <NSObject>

- (NSString * _Nonnull)displayNameForPhoneIdentifier:(NSString * _Nullable)phoneNumber;
- (NSArray<Contact *> * _Nonnull)signalContacts;
+ (BOOL)name:(NSString * _Nonnull)nameString matchesQuery:(NSString * _Nonnull)queryString;

#if TARGET_OS_IPHONE
- (UIImage * _Nullable)imageForPhoneIdentifier:(NSString * _Nullable)phoneNumber;
#endif

@end
