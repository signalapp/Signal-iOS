//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AES_CBC : NSObject

/**
 *  Encrypts with AES in CBC mode
 *
 *  @param data     data to encrypt
 *  @param key      AES key
 *  @param iv       Initialization vector for CBC
 *
 *  @return         ciphertext
 */

+ (NSData *)throws_encryptCBCMode:(NSData *)data
                          withKey:(NSData *)key
                           withIV:(NSData *)iv NS_SWIFT_UNAVAILABLE("throws objc exceptions");

/**
 *  Decrypts with AES in CBC mode
 *
 *  @param data     data to decrypt
 *  @param key      AES key
 *  @param iv       Initialization vector for CBC
 *
 *  @return         plaintext
 */

+ (NSData *)throws_decryptCBCMode:(NSData *)data
                          withKey:(NSData *)key
                           withIV:(NSData *)iv NS_SWIFT_UNAVAILABLE("throws objc exceptions");

@end

NS_ASSUME_NONNULL_END
