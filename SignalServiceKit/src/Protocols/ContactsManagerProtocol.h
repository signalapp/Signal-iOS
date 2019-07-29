//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class CNContact;
@class Contact;
@class PhoneNumber;
@class SDSAnyReadTransaction;
@class SignalAccount;
@class SignalServiceAddress;
@class UIImage;

@protocol ContactsManagerProtocol <NSObject>

- (NSString *)displayNameForAddress:(SignalServiceAddress *)address;
- (NSString *)displayNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;
- (NSArray<SignalAccount *> *)signalAccounts;

- (BOOL)isSystemContact:(NSString *)phoneNumber;
- (BOOL)isSystemContactWithSignalAccount:(NSString *)phoneNumber;

- (NSComparisonResult)compareSignalAccount:(SignalAccount *)left
                         withSignalAccount:(SignalAccount *)right NS_SWIFT_NAME(compare(signalAccount:with:));

#pragma mark - CNContacts

- (nullable CNContact *)cnContactWithId:(nullable NSString *)contactId;
- (nullable NSData *)avatarDataForCNContactId:(nullable NSString *)contactId;
- (nullable UIImage *)avatarImageForCNContactId:(nullable NSString *)contactId;

@end

NS_ASSUME_NONNULL_END
