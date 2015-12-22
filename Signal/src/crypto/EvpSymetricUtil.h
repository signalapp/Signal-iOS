#import <Foundation/Foundation.h>
#import <openssl/evp.h>

// Implements Symetric encryption methods using Openssl EVP Api. Raises Exceptions on failure.

@interface EvpSymetricUtil : NSObject

+ (NSData *)encryptMessage:(NSData *)message usingAes128WithCbcAndPaddingAndKey:(NSData *)key andIv:(NSData *)iv;
+ (NSData *)decryptMessage:(NSData *)message usingAes128WithCbcAndPaddingAndKey:(NSData *)key andIv:(NSData *)iv;

+ (NSData *)encryptMessage:(NSData *)message usingAes128WithCfbAndKey:(NSData *)key andIv:(NSData *)iv;
+ (NSData *)decryptMessage:(NSData *)message usingAes128WithCfbAndKey:(NSData *)key andIv:(NSData *)iv;

+ (NSData *)encryptMessage:(NSData *)message usingAes128InCounterModeAndKey:(NSData *)key andIv:(NSData *)iv;
+ (NSData *)decryptMessage:(NSData *)message usingAes128InCounterModeAndKey:(NSData *)key andIv:(NSData *)iv;
@end
