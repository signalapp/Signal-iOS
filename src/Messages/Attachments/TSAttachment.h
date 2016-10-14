//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSAttachment : TSYapDatabaseObject {

@protected
    NSString *_contentType;
}

@property (atomic, readwrite) UInt64 serverId;
@property (atomic, readwrite) NSData *encryptionKey;
@property (nonatomic, readonly) NSString *contentType;

- (instancetype)initWithServerId:(UInt64)serverId
                   encryptionKey:(NSData *)encryptionKey
                     contentType:(NSString *)contentType;

@end

NS_ASSUME_NONNULL_END
