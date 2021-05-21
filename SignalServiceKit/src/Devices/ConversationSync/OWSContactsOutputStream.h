//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSChunkedOutputStream.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSDisappearingMessagesConfiguration;
@class OWSRecipientIdentity;
@class SignalAccount;

@protocol ContactsManagerProtocol;

@interface OWSContactsOutputStream : OWSChunkedOutputStream

- (void)writeSignalAccount:(SignalAccount *)signalAccount
                    recipientIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
                       profileKeyData:(nullable NSData *)profileKeyData
                      contactsManager:(id<ContactsManagerProtocol>)contactsManager
    disappearingMessagesConfiguration:(nullable OWSDisappearingMessagesConfiguration *)disappearingMessagesConfiguration
                           isArchived:(nullable NSNumber *)isArchived
                        inboxPosition:(nullable NSNumber *)inboxPosition;

@end

NS_ASSUME_NONNULL_END
