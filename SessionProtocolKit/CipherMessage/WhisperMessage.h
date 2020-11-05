//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "CipherMessage.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ECKeyPair;

@interface WhisperMessage : NSObject <CipherMessage>

@property (nonatomic, readonly) int version;
@property (nonatomic, readonly) NSData *senderRatchetKey;
@property (nonatomic, readonly) int previousCounter;
@property (nonatomic, readonly) int counter;
@property (nonatomic, readonly) NSData *cipherText;
@property (nonatomic, readonly) NSData *serialized;

- (instancetype)init_throws_withData:(NSData *)serialized NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (nullable instancetype)initWithData:(NSData *)serialized error:(NSError **)outError;

- (instancetype)init_throws_withVersion:(int)version
                                 macKey:(NSData *)macKey
                       senderRatchetKey:(NSData *)senderRatchetKey
                                counter:(int)counter
                        previousCounter:(int)previousCounter
                             cipherText:(NSData *)cipherText
                      senderIdentityKey:(NSData *)senderIdentityKey
                    receiverIdentityKey:(NSData *)receiverIdentityKey NS_SWIFT_UNAVAILABLE("throws objc exceptions");

- (void)throws_verifyMacWithVersion:(int)messageVersion
                  senderIdentityKey:(NSData *)senderIdentityKey
                receiverIdentityKey:(NSData *)receiverIdentityKey
                             macKey:(NSData *)macKey NS_SWIFT_UNAVAILABLE("throws objc exceptions");

@end

NS_ASSUME_NONNULL_END
