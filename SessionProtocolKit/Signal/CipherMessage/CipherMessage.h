//
//  CipherMessage.h
//  AxolotlKit
//
//  Created by Frederic Jacobs on 26/10/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, CipherMessageType) {
    CipherMessageType_Prekey = 0,
    CipherMessageType_Whisper,
    CipherMessageType_Fallback = 3,
    CipherMessageType_ClosedGroupCiphertext = 4
};

@protocol CipherMessage <NSObject>

- (NSData *)serialized;

@property (nonatomic, readonly) CipherMessageType cipherMessageType;

@end
