//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "NSData+Image.h"
#import "NSData+keyVersionByte.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSContactsOutputStream.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSRecipientIdentity.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSContactThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSContactsOutputStream

- (void)writeSignalAccount:(SignalAccount *)signalAccount
                    recipientIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
                       profileKeyData:(nullable NSData *)profileKeyData
                      contactsManager:(id<ContactsManagerProtocol>)contactsManager
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

    if (isArchived != nil) {
        [contactBuilder setArchived:isArchived.boolValue];
    }

    if (inboxPosition != nil) {
        [contactBuilder setInboxPosition:inboxPosition.intValue];
    }

    if (recipientIdentity != nil) {
        if (recipientIdentity.verificationState == OWSVerificationStateNoLongerVerified) {
            // We only sync user's marking as un/verified. Never sync the conflicted state, the sibling device
            // will figure that out on it's own.
            return;
        }

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
