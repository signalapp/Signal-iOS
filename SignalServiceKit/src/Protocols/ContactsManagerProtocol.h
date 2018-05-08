//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@class Contact;
@class PhoneNumber;
@class SignalAccount;
@class UIImage;

@protocol ContactsManagerProtocol <NSObject>

- (NSString * _Nonnull)displayNameForPhoneIdentifier:(NSString * _Nullable)phoneNumber;
- (NSArray<SignalAccount *> * _Nonnull)signalAccounts;

- (BOOL)isSystemContact:(NSString *)recipientId;
- (BOOL)isSystemContactWithSignalAccount:(NSString *)recipientId;

@end
