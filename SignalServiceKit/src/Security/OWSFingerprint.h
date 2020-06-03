//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;
@class UIImage;

@interface OWSFingerprint : NSObject

#pragma mark - Initializers

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithMyStableAddress:(SignalServiceAddress *)myStableAddress
                          myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                     theirStableAddress:(SignalServiceAddress *)theirStableAddress
                       theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType
                              theirName:(NSString *)theirName
                         hashIterations:(uint32_t)hashIterations NS_DESIGNATED_INITIALIZER;

+ (instancetype)fingerprintWithMyStableAddress:(SignalServiceAddress *)myStableAddress
                                 myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                            theirStableAddress:(SignalServiceAddress *)theirStableAddress
                              theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType
                                     theirName:(NSString *)theirName
                                hashIterations:(uint32_t)hashIterations;

+ (instancetype)fingerprintWithMyStableAddress:(SignalServiceAddress *)myStableAddress
                                 myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                            theirStableAddress:(SignalServiceAddress *)theirStableAddress
                              theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType
                                     theirName:(NSString *)theirName;

#pragma mark - Properties

@property (nonatomic, readonly) SignalServiceAddress *myStableAddress;
@property (nonatomic, readonly) NSData *myIdentityKey;
@property (nonatomic, readonly) SignalServiceAddress *theirStableAddress;
@property (nonatomic, readonly) NSData *theirIdentityKey;
@property (nonatomic, readonly) NSString *displayableText;
@property (nullable, nonatomic, readonly) UIImage *image;

#pragma mark - Instance Methods

- (BOOL)matchesLogicalFingerprintsData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
