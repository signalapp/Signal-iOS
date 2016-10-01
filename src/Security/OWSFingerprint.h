//  Created by Michael Kirk on 9/14/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class UIImage;

@interface OWSFingerprint : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithMyStableId:(NSString *)myStableId
                     myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                     theirStableId:(NSString *)theirStableId
                  theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType
                    hashIterations:(uint32_t)hashIterations NS_DESIGNATED_INITIALIZER;

+ (instancetype)fingerprintWithMyStableId:(NSString *)myStableId
                            myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                            theirStableId:(NSString *)theirStableId
                         theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType
                           hashIterations:(uint32_t)hashIterations;

+ (instancetype)fingerprintWithMyStableId:(NSString *)myStableId
                            myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                            theirStableId:(NSString *)theirStableId
                         theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType;

- (BOOL)matchesCombinedFingerprintData:(NSData *)combinedFingerprintData error:(NSError **)error;

@property (nonatomic, readonly) NSData *myStableIdData;
@property (nonatomic, readonly) NSData *myIdentityKey;
@property (nonatomic, readonly) NSString *theirStableId;
@property (nonatomic, readonly) NSData *theirStableIdData;
@property (nonatomic, readonly) NSData *theirIdentityKey;
@property (nonatomic, readonly) NSString *displayableText;
@property (nonatomic, readonly) UIImage *image;

@end

NS_ASSUME_NONNULL_END
