//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class CNContact;
@class Contact;
@class PhoneNumber;
@class SignalAccount;
@class SignalServiceAddress;
@class UIImage;
@class YapDatabaseReadTransaction;

@protocol ContactsManagerProtocol <NSObject>

- (NSString *)displayNameForAddress:(nullable SignalServiceAddress *)address;
- (NSString *)displayNameForAddress:(nullable SignalServiceAddress *)address
                        transaction:(YapDatabaseReadTransaction *)transaction;
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
