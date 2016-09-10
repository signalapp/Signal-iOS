//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSContactsOutputStream.h"
#import "Contact.h"
#import "MIMETypeUtil.h"
#import "OWSSignalServiceProtos.pb.h"
#import <ProtocolBuffers/CodedOutputStream.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSContactsOutputStream

- (void)writeContact:(Contact *)contact
{
    OWSSignalServiceProtosContactDetailsBuilder *contactBuilder = [OWSSignalServiceProtosContactDetailsBuilder new];
    [contactBuilder setName:contact.fullName];
    [contactBuilder setNumber:contact.textSecureIdentifiers.firstObject];

    NSData *avatarPng;
    if (contact.image) {
        OWSSignalServiceProtosContactDetailsAvatarBuilder *avatarBuilder =
            [OWSSignalServiceProtosContactDetailsAvatarBuilder new];

        [avatarBuilder setContentType:OWSMimeTypeImagePng];
        avatarPng = UIImagePNGRepresentation(contact.image);
        [avatarBuilder setLength:(uint32_t)avatarPng.length];
        [contactBuilder setAvatarBuilder:avatarBuilder];
    }

    NSData *contactData = [[contactBuilder build] data];

    uint32_t contactDataLength = (uint32_t)contactData.length;
    [self.delegateStream writeRawVarint32:contactDataLength];
    [self.delegateStream writeRawData:contactData];

    if (contact.image) {
        [self.delegateStream writeRawData:avatarPng];
    }
}

@end

NS_ASSUME_NONNULL_END
