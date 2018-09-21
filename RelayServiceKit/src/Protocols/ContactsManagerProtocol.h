//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

//@class CNContact;
//@class Contact;
//@class PhoneNumber;
@class RelayRecipient;
@class UIImage;

@protocol ContactsManagerProtocol <NSObject>

- (nullable NSString *)displayNameForRecipientId:(NSString *)recipientId;
- (nullable NSString *)cachedDisplayNameForRecipientId:(NSString *)recipientId;

- (NSArray<RelayRecipient *> *)allRecipients;

- (BOOL)isSystemContact:(NSString *)recipientId;
- (BOOL)isSystemContactWithRecipientId:(NSString *)recipientId;

- (NSComparisonResult)compareRecpient:(RelayRecipient *)left
                         withRecipient:(RelayRecipient *)right NS_SWIFT_NAME(compare(recipient:with:));

-(nullable RelayRecipient *)recipientWithId:(NSString *)recipientId;
//- (nullable CNContact *)cnContactWithId:(nullable NSString *)contactId;
//- (nullable NSData *)avatarDataForCNContactId:(nullable NSString *)contactId;
- (nullable UIImage *)avatarImageRecipientId:(NSString *)recipientId;

@end

NS_ASSUME_NONNULL_END
