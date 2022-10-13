//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
                        inboxPosition:(nullable NSNumber *)inboxPosition
                            isBlocked:(BOOL)isBlocked;

@end

NS_ASSUME_NONNULL_END
