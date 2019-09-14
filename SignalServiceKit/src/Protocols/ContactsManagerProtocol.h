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
@class TSThread;
@class UIImage;

@protocol ContactsManagerProtocol <NSObject>

/// The name representing this address.
///
/// This will be the first of the following that exists for this address:
/// - The matching name from system contacts
/// - The name provided on the profile
/// - The address' phone number
/// - The address' UUID
- (NSString *)displayNameForAddress:(SignalServiceAddress *)address;
- (NSString *)displayNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;
- (NSString *)displayNameForSignalAccount:(SignalAccount *)signalAccount;

- (NSString *)displayNameForThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;
- (NSString *)displayNameForThreadWithSneakyTransaction:(TSThread *)thread
    NS_SWIFT_NAME(displayNameWithSneakyTransaction(thread:));

- (NSArray<SignalAccount *> *)signalAccounts;

- (BOOL)isSystemContactWithPhoneNumber:(NSString *)phoneNumber NS_SWIFT_NAME(isSystemContact(phoneNumber:));
- (BOOL)isSystemContactWithAddress:(SignalServiceAddress *)address NS_SWIFT_NAME(isSystemContact(address:));

- (BOOL)isSystemContactWithSignalAccount:(NSString *)phoneNumber;

- (NSComparisonResult)compareSignalAccount:(SignalAccount *)left
                         withSignalAccount:(SignalAccount *)right NS_SWIFT_NAME(compare(signalAccount:with:));

#pragma mark - CNContacts

- (nullable CNContact *)cnContactWithId:(nullable NSString *)contactId;
- (nullable NSData *)avatarDataForCNContactId:(nullable NSString *)contactId;
- (nullable UIImage *)avatarImageForCNContactId:(nullable NSString *)contactId;

@end

NS_ASSUME_NONNULL_END
