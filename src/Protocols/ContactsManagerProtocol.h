//
//  ContactsManagerProtocol.h
//  Pods
//
//  Created by Frederic Jacobs on 05/12/15.
//
//

#import <Foundation/Foundation.h>

@class PhoneNumber;

@protocol ContactsManagerProtocol <NSObject>

- (NSString *)nameStringForPhoneIdentifier:(NSString *)phoneNumber;
+ (BOOL)name:(NSString *)nameString matchesQuery:(NSString *)queryString;

#if TARGET_OS_IPHONE
- (UIImage *)imageForPhoneIdentifier:(NSString *)phoneNumber;
#endif

@end
