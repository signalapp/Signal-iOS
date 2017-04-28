//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class Contact;

// We want to be able to present contacts with multiple signal
// accounts in the UI.  This class represents a given (contact,
// signal account) tuple.
@interface ContactAccount : NSObject

@property (nonatomic) Contact *contact;

// An E164 value identifying the signal account.
@property (nonatomic) NSString *recipientId;

@property (nonatomic) BOOL isMultipleAccountContact;

// For contacts with more than one signal account,
// this is a label for the account.
@property (nonatomic) NSString *multipleAccountLabel;

@end

NS_ASSUME_NONNULL_END
