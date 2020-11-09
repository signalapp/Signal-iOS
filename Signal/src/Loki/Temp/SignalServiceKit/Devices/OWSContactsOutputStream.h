//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSChunkedOutputStream.h"

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
     conversationColorName:(NSString *)conversationColorName
disappearingMessagesConfiguration:(nullable OWSDisappearingMessagesConfiguration *)disappearingMessagesConfiguration;


@end

NS_ASSUME_NONNULL_END
