//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsOutputStream.h"
#import "Contact.h"
#import "MIMETypeUtil.h"
#import "OWSSignalServiceProtos.pb.h"
#import "SignalAccount.h"
#import <ProtocolBuffers/CodedOutputStream.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSContactsOutputStream

- (void)writeSignalAccount:(SignalAccount *)signalAccount
{
    OWSAssert(signalAccount);
    OWSAssert(signalAccount.contact);
    
    OWSSignalServiceProtosContactDetailsBuilder *contactBuilder = [OWSSignalServiceProtosContactDetailsBuilder new];
    [contactBuilder setName:signalAccount.contact.fullName];
    [contactBuilder setNumber:signalAccount.recipientId];

    NSData *avatarPng;
    if (signalAccount.contact.image) {
        OWSSignalServiceProtosContactDetailsAvatarBuilder *avatarBuilder =
            [OWSSignalServiceProtosContactDetailsAvatarBuilder new];

        [avatarBuilder setContentType:OWSMimeTypeImagePng];
        avatarPng = UIImagePNGRepresentation(signalAccount.contact.image);
        [avatarBuilder setLength:(uint32_t)avatarPng.length];
        [contactBuilder setAvatarBuilder:avatarBuilder];
    }

    NSData *contactData = [[contactBuilder build] data];

    uint32_t contactDataLength = (uint32_t)contactData.length;
    [self.delegateStream writeRawVarint32:contactDataLength];
    [self.delegateStream writeRawData:contactData];

    if (signalAccount.contact.image) {
        [self.delegateStream writeRawData:avatarPng];
    }
}

@end

NS_ASSUME_NONNULL_END
