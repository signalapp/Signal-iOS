//
//  TSAttachementsTest.m
//  Signal
//
//  Created by Frederic Jacobs on 21/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "TSAttachmentStream.h"
#import "Cryptography.h"

@interface TSAttachmentsTest : XCTestCase

@end

@implementation TSAttachmentsTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testAttachmentEncryptionDecryption {
    NSData *plaintext = [Cryptography generateRandomBytes:100];
    NSString *contentType = @"img/jpg";
    uint64_t identifier   = 3063578577793591963;
    NSNumber *number      = [NSNumber numberWithUnsignedLongLong:identifier];
    
    TSAttachmentEncryptionResult *encryptionResult = [Cryptography encryptAttachment:plaintext contentType:contentType identifier:[number stringValue]];
    
    NSData *plaintextBis = [Cryptography decryptAttachment:encryptionResult.body withKey:encryptionResult.pointer.encryptionKey];
    
    XCTAssert([plaintext isEqualToData:plaintextBis], @"Attachments encryption failed");
}

@end
