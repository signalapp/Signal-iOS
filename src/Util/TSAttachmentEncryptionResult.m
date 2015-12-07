//
//  TSAttachmentEncryptionResult.m
//  Signal
//
//  Created by Frederic Jacobs on 21/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSAttachmentEncryptionResult.h"

@implementation TSAttachmentEncryptionResult

- (instancetype)initWithPointer:(TSAttachmentStream *)pointer body:(NSData *)cipherText {
    self = [super init];

    if (self) {
        _body    = cipherText;
        _pointer = pointer;
    }

    return self;
}

@end
