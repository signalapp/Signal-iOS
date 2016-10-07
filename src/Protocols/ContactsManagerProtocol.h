//  Created by Frederic Jacobs on 05/12/15.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

@class PhoneNumber;
@class Contact;
@class UIImage;

@protocol ContactsManagerProtocol <NSObject>

- (NSString *)nameStringForPhoneIdentifier:(NSString *)phoneNumber;
- (NSArray<Contact *> *)signalContacts;
+ (BOOL)name:(NSString *)nameString matchesQuery:(NSString *)queryString;

#if TARGET_OS_IPHONE
- (UIImage *)imageForPhoneIdentifier:(NSString *)phoneNumber;
#endif

@end
