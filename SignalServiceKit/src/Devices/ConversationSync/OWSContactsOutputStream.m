//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsOutputStream.h"
#import "Contact.h"
#import "ContactsManagerProtocol.h"
#import "MIMETypeUtil.h"
#import "NSData+Image.h"
#import "NSData+keyVersionByte.h"
#import "OWSBlockingManager.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSRecipientIdentity.h"
#import "SignalAccount.h"
#import "TSContactThread.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSContactsOutputStream

- (void)writeSignalAccount:(SignalAccount *)signalAccount
                    recipientIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
                       profileKeyData:(nullable NSData *)profileKeyData
                      contactsManager:(id<ContactsManagerProtocol>)contactsManager
                conversationColorName:(NSString *)conversationColorName
    disappearingMessagesConfiguration:(nullable OWSDisappearingMessagesConfiguration *)disappearingMessagesConfiguration
                           isArchived:(nullable NSNumber *)isArchived
                        inboxPosition:(nullable NSNumber *)inboxPosition
{
    OWSAssertDebug(signalAccount);
    OWSAssertDebug(signalAccount.contact);
    OWSAssertDebug(contactsManager);

    SSKProtoContactDetailsBuilder *contactBuilder = [SSKProtoContactDetails builder];
    [contactBuilder setContactE164:signalAccount.recipientAddress.phoneNumber];
    [contactBuilder setContactUuid:signalAccount.recipientAddress.uuidString];
    [contactBuilder setName:signalAccount.contact.fullName];
    [contactBuilder setColor:conversationColorName];

    if (isArchived != nil) {
        [contactBuilder setArchived:isArchived.boolValue];
    }

    if (inboxPosition != nil) {
        [contactBuilder setInboxPosition:inboxPosition.intValue];
    }

    if (recipientIdentity != nil) {
        SSKProtoVerified *_Nullable verified = BuildVerifiedProtoWithAddress(signalAccount.recipientAddress,
            [recipientIdentity.identityKey prependKeyType],
            recipientIdentity.verificationState,
            0);
        if (!verified) {
            OWSLogError(@"could not build protobuf.");
            return;
        }
        contactBuilder.verified = verified;
    }

    NSData *_Nullable avatarJpegData = signalAccount.contactAvatarJpegData;
    if (avatarJpegData != nil) {
        SSKProtoContactDetailsAvatarBuilder *avatarBuilder = [SSKProtoContactDetailsAvatar builder];
        [avatarBuilder setContentType:OWSMimeTypeImageJpeg];
        [avatarBuilder setLength:(uint32_t)avatarJpegData.length];

        NSError *error;
        SSKProtoContactDetailsAvatar *_Nullable avatar = [avatarBuilder buildAndReturnError:&error];
        if (error || !avatar) {
            OWSLogError(@"could not build protobuf: %@", error);
            return;
        }
        [contactBuilder setAvatar:avatar];
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

    if ([OWSBlockingManager.shared isAddressBlocked:signalAccount.recipientAddress]) {
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

    if (avatarJpegData != nil) {
        [self writeData:avatarJpegData];
    }
}

@end

NS_ASSUME_NONNULL_END
