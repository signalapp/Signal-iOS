#import <Foundation/Foundation.h>

// Implements class level functions for Openssl's EVP_Digest Api

@interface EvpMessageDigest : NSObject

+ (NSData *)hashWithSha256:(NSData *)data;
+ (NSData *)hmacUsingSha1Data:(NSData *)data withKey:(NSData *)key;
+ (NSData *)hmacUsingSha256Data:(NSData *)data withKey:(NSData *)key;
@end
