//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class Contact;
@class PhoneNumber;
@class SignalAccount;
@class UIImage;

@protocol ContactsManagerProtocol <NSObject>

- (NSString * _Nonnull)displayNameForPhoneIdentifier:(NSString * _Nullable)phoneNumber;
- (NSArray<SignalAccount *> * _Nonnull)signalAccounts;

#if TARGET_OS_IPHONE
- (UIImage * _Nullable)imageForPhoneIdentifier:(NSString * _Nullable)phoneNumber;
#endif

@end
