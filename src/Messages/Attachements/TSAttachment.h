//
//  TSAttachment.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSYapDatabaseObject.h"

@interface TSAttachment : TSYapDatabaseObject

- (NSNumber *)identifier;

@property (nonatomic, readonly) NSData *encryptionKey;
@property (nonatomic, readonly) NSString *contentType;

- (instancetype)initWithIdentifier:(NSString *)identifier
                     encryptionKey:(NSData *)encryptionKey
                       contentType:(NSString *)contentType;


@end
