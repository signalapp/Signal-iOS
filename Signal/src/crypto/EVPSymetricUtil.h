#import <Foundation/Foundation.h>
#import <openssl/evp.h>

// Implements Symetric encryption methods using Openssl EVP Api. Raises Exceptions on failure.

@interface EVPSymetricUtil : NSObject

+ (NSData*)encryptMessage:(NSData*)message usingAES128WithCBCAndPaddingAndKey:(NSData*)key andIV:(NSData*)iv;
+ (NSData*)decryptMessage:(NSData*)message usingAES128WithCBCAndPaddingAndKey:(NSData*)key andIV:(NSData*)iv;

+ (NSData*)encryptMessage:(NSData*)message usingAES128WithCFBAndKey:(NSData*)key andIV:(NSData*)iv;
+ (NSData*)decryptMessage:(NSData*)message usingAES128WithCFBAndKey:(NSData*)key andIV:(NSData*)iv;

+ (NSData*)encryptMessage:(NSData*)message usingAES128InCounterModeAndKey:(NSData*)key andIV:(NSData*)iv;
+ (NSData*)decryptMessage:(NSData*)message usingAES128InCounterModeAndKey:(NSData*)key andIV:(NSData*)iv;

@end
