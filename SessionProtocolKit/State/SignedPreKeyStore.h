//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignedPrekeyRecord.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SignedPreKeyStore <NSObject>

- (SignedPreKeyRecord *)throws_loadSignedPrekey:(int)signedPreKeyId NS_SWIFT_UNAVAILABLE("throws objc exceptions");

- (nullable SignedPreKeyRecord *)loadSignedPrekeyOrNil:(int)signedPreKeyId;

- (NSArray<SignedPreKeyRecord *> *)loadSignedPreKeys;

- (void)storeSignedPreKey:(int)signedPreKeyId signedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord;

- (BOOL)containsSignedPreKey:(int)signedPreKeyId;

- (void)removeSignedPreKey:(int)signedPrekeyId;

@end

NS_ASSUME_NONNULL_END
