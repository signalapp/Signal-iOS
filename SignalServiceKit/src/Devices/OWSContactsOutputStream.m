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
#import "SignalAccount.h"
#import "TSContactThread.h"
#import <ProtocolBuffers/CodedOutputStream.h>
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
    OWSAssert(signalAccount);
    OWSAssert(signalAccount.contact);
    OWSAssert(contactsManager);

    SSKProtoContactDetailsBuilder *contactBuilder = [SSKProtoContactDetailsBuilder new];
    [contactBuilder setName:signalAccount.contact.fullName];
    [contactBuilder setNumber:signalAccount.recipientId];
#ifdef CONVERSATION_COLORS_ENABLED
    [contactBuilder setColor:conversationColorName];
#endif

    if (recipientIdentity != nil) {
        SSKProtoVerifiedBuilder *verifiedBuilder = [SSKProtoVerifiedBuilder new];
        verifiedBuilder.destination = recipientIdentity.recipientId;
        verifiedBuilder.identityKey = [recipientIdentity.identityKey prependKeyType];
        verifiedBuilder.state = OWSVerificationStateToProtoState(recipientIdentity.verificationState);

        NSError *error;
        SSKProtoVerified *_Nullable verified = [verifiedBuilder buildAndReturnError:&error];
        if (error || !verified) {
            OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
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
                OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
                return;
            }
            [contactBuilder setAvatar:avatar];
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

    if (disappearingMessagesConfiguration && disappearingMessagesConfiguration.isEnabled) {
        [contactBuilder setExpireTimer:disappearingMessagesConfiguration.durationSeconds];
    }

    if ([OWSBlockingManager.sharedManager isRecipientIdBlocked:signalAccount.recipientId]) {
        [contactBuilder setBlocked:YES];
    }

    NSError *error;
    SSKProtoContactDetails *_Nullable contactProto = [contactBuilder buildAndReturnError:&error];
    if (error || !contactProto) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return;
    }
    NSData *_Nullable contactData = [contactProto serializedDataAndReturnError:&error];
    if (error || !contactData) {
        OWSFail(@"%@ could not serialize protobuf: %@", self.logTag, error);
        return;
    }

    uint32_t contactDataLength = (uint32_t)contactData.length;
    [self.delegateStream writeRawVarint32:contactDataLength];
    [self.delegateStream writeRawData:contactData];

    if (avatarPng) {
        [self.delegateStream writeRawData:avatarPng];
    }
}

@end

NS_ASSUME_NONNULL_END
