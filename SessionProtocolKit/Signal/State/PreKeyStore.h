//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "PreKeyRecord.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PreKeyStore <NSObject>

- (PreKeyRecord *)throws_loadPreKey:(int)preKeyId NS_SWIFT_UNAVAILABLE("throws objc exceptions");

- (void)storePreKey:(int)preKeyId preKeyRecord:(PreKeyRecord *)record;

- (BOOL)containsPreKey:(int)preKeyId;

- (void)removePreKey:(int)preKeyId protocolContext:(nullable id)protocolContext;

@end

NS_ASSUME_NONNULL_END
