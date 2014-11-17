#import <Foundation/Foundation.h>

// Implements class level functions for Openssl's EVP_Digest Api

@interface EvpMessageDigest : NSObject

+ (NSData*)hashWithSHA256:(NSData*)data;
+ (NSData*)hmacUsingSHA1Data:(NSData*)data withKey:(NSData*)key;
+ (NSData*)hmacUsingSHA256Data:(NSData*)data withKey:(NSData*)key;

@end
