//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsOutputStream.h"
#import "Contact.h"
#import "ContactsManagerProtocol.h"
#import "Cryptography.h"
#import "MIMETypeUtil.h"
#import "NSData+keyVersionByte.h"
#import "OWSBlockingManager.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSRecipientIdentity.h"
#import "OWSSignalServiceProtos.pb.h"
#import "SignalAccount.h"
#import "TSContactThread.h"
#import <ProtocolBuffers/CodedOutputStream.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSContactsOutputStream

- (void)writeSignalAccount:(SignalAccount *)signalAccount
         recipientIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
            profileKeyData:(nullable NSData *)profileKeyData
           contactsManager:(id<ContactsManagerProtocol>)contactsManager
{
    OWSAssert(signalAccount);
    OWSAssert(signalAccount.contact);
    OWSAssert(contactsManager);

    OWSSignalServiceProtosContactDetailsBuilder *contactBuilder = [OWSSignalServiceProtosContactDetailsBuilder new];
    [contactBuilder setName:signalAccount.contact.fullName];
    [contactBuilder setNumber:signalAccount.recipientId];

    if (recipientIdentity != nil) {
        OWSSignalServiceProtosVerifiedBuilder *verifiedBuilder = [OWSSignalServiceProtosVerifiedBuilder new];
        verifiedBuilder.destination = recipientIdentity.recipientId;
        verifiedBuilder.identityKey = [recipientIdentity.identityKey prependKeyType];
        verifiedBuilder.state = OWSVerificationStateToProtoState(recipientIdentity.verificationState);
        contactBuilder.verifiedBuilder = verifiedBuilder;
    }

    UIImage *_Nullable rawAvatar = [contactsManager avatarImageForCNContactId:signalAccount.contact.cnContactId];
    NSData *_Nullable avatarPng;
    if (rawAvatar) {
        avatarPng = UIImagePNGRepresentation(rawAvatar);
        if (avatarPng) {
            OWSSignalServiceProtosContactDetailsAvatarBuilder *avatarBuilder =
                [OWSSignalServiceProtosContactDetailsAvatarBuilder new];

            [avatarBuilder setContentType:OWSMimeTypeImagePng];
            [avatarBuilder setLength:(uint32_t)avatarPng.length];
            [contactBuilder setAvatarBuilder:avatarBuilder];
        }
    }

    if (profileKeyData) {
        OWSAssert(profileKeyData.length == kAES256_KeyByteLength);
        [contactBuilder setProfileKey:profileKeyData];
    }

    // Always ensure the "expire timer" property is set so that desktop
    // can easily distinguish between a modern client declaring "off" vs a
    // legacy client "not specifying".
    [contactBuilder setExpireTimer:0];

    TSContactThread *_Nullable contactThread = [TSContactThread getThreadWithContactId:signalAccount.recipientId];
    if (contactThread) {
        OWSDisappearingMessagesConfiguration *_Nullable disappearingMessagesConfiguration =
            [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:contactThread.uniqueId];

        if (disappearingMessagesConfiguration && disappearingMessagesConfiguration.isEnabled) {
            [contactBuilder setExpireTimer:disappearingMessagesConfiguration.durationSeconds];
        }
    }

    if ([OWSBlockingManager.sharedManager isRecipientIdBlocked:signalAccount.recipientId]) {
        [contactBuilder setBlocked:YES];
    }

    NSData *contactData = [[contactBuilder build] data];

    uint32_t contactDataLength = (uint32_t)contactData.length;
    [self.delegateStream writeRawVarint32:contactDataLength];
    [self.delegateStream writeRawData:contactData];

    if (avatarPng) {
        [self.delegateStream writeRawData:avatarPng];
    }
}

@end

NS_ASSUME_NONNULL_END
