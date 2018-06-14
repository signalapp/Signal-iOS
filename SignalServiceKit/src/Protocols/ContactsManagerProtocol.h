//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class Contact;
@class PhoneNumber;
@class SignalAccount;
@class UIImage;

@protocol ContactsManagerProtocol <NSObject>

- (NSString *)displayNameForPhoneIdentifier:(NSString *_Nullable)phoneNumber;
- (NSArray<SignalAccount *> *)signalAccounts;

- (BOOL)isSystemContact:(NSString *)recipientId;
- (BOOL)isSystemContactWithSignalAccount:(NSString *)recipientId;

- (NSComparisonResult)compareSignalAccount:(SignalAccount *)left
                         withSignalAccount:(SignalAccount *)right NS_SWIFT_NAME(compare(signalAccount:with:));

@end

NS_ASSUME_NONNULL_END
