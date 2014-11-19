//
//  TSAttachement.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSYapDatabaseObject.h"

/**
 *  TSAttachements are stored by attachement id;
 */

@interface TSAttachement : TSYapDatabaseObject

@property (nonatomic, readonly) NSString *contentType;
@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) NSData *encryptionKey;

- (BOOL)expired;
- (NSString*)attachementId;

- (instancetype)initWithAttachementId:(NSString*)attachementId url:(NSURL*)url encryptionKey:(NSData*)encryptionKey;

@end
