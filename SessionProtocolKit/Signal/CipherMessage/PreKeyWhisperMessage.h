//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "WhisperMessage.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PreKeyWhisperMessage : NSObject <CipherMessage>

- (instancetype)init_throws_withData:(NSData *)serialized NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (nullable instancetype)initWithData:(NSData *)serialized error:(NSError **)outError;

- (instancetype)init_throws_withWhisperMessage:(WhisperMessage *)whisperMessage
                                registrationId:(int)registrationId
                                      prekeyId:(int)prekeyId
                                signedPrekeyId:(int)signedPrekeyId
                                       baseKey:(NSData *)baseKey
                                   identityKey:(NSData *)identityKey NS_SWIFT_UNAVAILABLE("throws objc exceptions");

@property (nonatomic, readonly) int registrationId;
@property (nonatomic, readonly) int version;
@property (nonatomic, readonly) int prekeyID;
@property (nonatomic, readonly) int signedPrekeyId;
@property (nonatomic, readonly) NSData *baseKey;
@property (nonatomic, readonly) NSData *identityKey;
@property (nonatomic, readonly) WhisperMessage *message;

@end

NS_ASSUME_NONNULL_END
