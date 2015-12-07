//
//  TSAttachmentEncryptionResult.h
//  Signal
//
//  Created by Frederic Jacobs on 21/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSAttachmentStream.h"

@interface TSAttachmentEncryptionResult : NSData

@property (readwrite) TSAttachmentStream *pointer;
@property (readonly) NSData *body;

- (instancetype)initWithPointer:(TSAttachmentStream *)pointer body:(NSData *)cipherText;

@end
