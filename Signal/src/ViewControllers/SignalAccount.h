//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class Contact;
@class SignalRecipient;

// This class represents a single valid Signal account.
//
// * Contacts with multiple signal accounts will correspond to
//   multiple instances of SignalAccount.
// * For non-contacts, the contact property will be nil.
//
// New instances of SignalAccount for active accounts are
// created every time we do a contacts intersection (e.g.
// in response to a change to the device contacts).
@interface SignalAccount : NSObject

// An E164 value identifying the signal account.
//
// This is the key property of this class and it
// will always be non-null.
@property (nonatomic, readonly) NSString *recipientId;

// This property is optional and will not be set for
// non-contact account.
@property (nonatomic, nullable) Contact *contact;

@property (nonatomic) BOOL isMultipleAccountContact;

// For contacts with more than one signal account,
// this is a label for the account.
@property (nonatomic) NSString *multipleAccountLabel;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithSignalRecipient:(SignalRecipient *)signalRecipient;

- (instancetype)initWithRecipientId:(NSString *)recipientId;

// In most cases this should be non-null. This should only
// be non-null in the case where the SignalRecipient was
// deleted before this property was accessed.
//
// NOTE: This may create a database transaction.
- (nullable SignalRecipient *)signalRecipient;

@end

NS_ASSUME_NONNULL_END
