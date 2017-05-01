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
// in response to a
@interface SignalAccount : NSObject

@property (nonatomic) SignalRecipient *signalRecipient;

// An E164 value identifying the signal account.
@property (nonatomic, readonly) NSString *recipientId;

// This property is optional and will not be set for
// non-contact account.
@property (nonatomic, nullable) Contact *contact;

@property (nonatomic) BOOL isMultipleAccountContact;

// For contacts with more than one signal account,
// this is a label for the account.
@property (nonatomic) NSString *multipleAccountLabel;

@end

NS_ASSUME_NONNULL_END
