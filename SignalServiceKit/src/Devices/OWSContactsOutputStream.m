//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsOutputStream.h"
#import "Contact.h"
#import "ContactsManagerProtocol.h"
#import "Cryptography.h"
#import "MIMETypeUtil.h"
#import "NSData+OWS.h"
#import "NSData+keyVersionByte.h"
#import "OWSBlockingManager.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSRecipientIdentity.h"
#import "SignalAccount.h"
#import "TSContactThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSContactsOutputStream

- (void)writeSignalAccount:(SignalAccount *)signalAccount
         recipientIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
            profileKeyData:(nullable NSData *)profileKeyData
           contactsManager:(id<ContactsManagerProtocol>)contactsManager
     conversationColorName:(NSString *)conversationColorName
disappearingMessagesConfiguration:(nullable OWSDisappearingMessagesConfiguration *)disappearingMessagesConfiguration
{
    OWSAssertDebug(signalAccount);
    OWSAssertDebug(signalAccount.contact);
    OWSAssertDebug(contactsManager);

    SSKProtoContactDetailsBuilder *contactBuilder = [SSKProtoContactDetailsBuilder new];
    [contactBuilder setName:signalAccount.contact.fullName];
    [contactBuilder setNumber:signalAccount.recipientId];
    [contactBuilder setColor:conversationColorName];

    if (recipientIdentity != nil) {
        SSKProtoVerified *_Nullable verified = BuildVerifiedProtoWithRecipientId(recipientIdentity.recipientId,
            [recipientIdentity.identityKey prependKeyType],
            recipientIdentity.verificationState,
            0);
        if (!verified) {
            OWSLogError(@"could not build protobuf.");
            return;
        }
        contactBuilder.verified = verified;
    }

    UIImage *_Nullable rawAvatar = [contactsManager avatarImageForCNContactId:signalAccount.contact.cnContactId];
    NSData *_Nullable avatarPng;
    if (rawAvatar) {
        avatarPng = UIImagePNGRepresentation(rawAvatar);
        if (avatarPng) {
            SSKProtoContactDetailsAvatarBuilder *avatarBuilder =
                [SSKProtoContactDetailsAvatarBuilder new];
            [avatarBuilder setContentType:OWSMimeTypeImagePng];
            [avatarBuilder setLength:(uint32_t)avatarPng.length];

            NSError *error;
            SSKProtoContactDetailsAvatar *_Nullable avatar = [avatarBuilder buildAndReturnError:&error];
            if (error || !avatar) {
                OWSLogError(@"could not build protobuf: %@", error);
                return;
            }
            [contactBuilder setAvatar:avatar];
        }
    }

    if (profileKeyData) {
        OWSAssertDebug(profileKeyData.length == kAES256_KeyByteLength);
        [contactBuilder setProfileKey:profileKeyData];
    }

    // Always ensure the "expire timer" property is set so that desktop
    // can easily distinguish between a modern client declaring "off" vs a
    // legacy client "not specifying".
    [contactBuilder setExpireTimer:0];

    if (disappearingMessagesConfiguration && disappearingMessagesConfiguration.isEnabled) {
        [contactBuilder setExpireTimer:disappearingMessagesConfiguration.durationSeconds];
    }

    if ([OWSBlockingManager.sharedManager isRecipientIdBlocked:signalAccount.recipientId]) {
        [contactBuilder setBlocked:YES];
    }

    NSError *error;
    NSData *_Nullable contactData = [contactBuilder buildSerializedDataAndReturnError:&error];
    if (error || !contactData) {
        OWSFailDebug(@"could not serialize protobuf: %@", error);
        return;
    }

    uint32_t contactDataLength = (uint32_t)contactData.length;
    [self writeVariableLengthUInt32:contactDataLength];
    [self writeData:contactData];

    if (avatarPng) {
        [self writeData:avatarPng];
    }
}

@end

NS_ASSUME_NONNULL_END
