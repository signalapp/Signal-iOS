//  Created by Frederic Jacobs on 21/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import <XCTest/XCTest.h>

#import "TSAttachmentStream.h"
#import "Cryptography.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSAttachmentsTest : XCTestCase

@end

@implementation TSAttachmentsTest

- (void)testAttachmentEncryptionDecryption
{
    NSData *plaintext = [Cryptography generateRandomBytes:100];

    NSData *encryptionKey;
    NSData *encryptedData = [Cryptography encryptAttachmentData:plaintext outKey:&encryptionKey];
    NSData *plaintextBis = [Cryptography decryptAttachment:encryptedData withKey:encryptionKey];

    XCTAssert([plaintext isEqualToData:plaintextBis], @"Attachments encryption failed");
}

@end

NS_ASSUME_NONNULL_END
