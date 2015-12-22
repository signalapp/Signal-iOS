#import <Foundation/Foundation.h>
#import "PhoneNumber.h"

@interface HttpRequest : NSObject

+ (HttpRequest *)httpRequestUnauthenticatedWithMethod:(NSString *)method
                                          andLocation:(NSString *)location
                                      andOptionalBody:(NSString *)optionalBody;

+ (HttpRequest *)httpRequestWithBasicAuthenticationAndMethod:(NSString *)method
                                                 andLocation:(NSString *)location
                                             andOptionalBody:(NSString *)optionalBody
                                              andLocalNumber:(NSString *)localNumber
                                                 andPassword:(NSString *)password;

+ (HttpRequest *)httpRequestWithOtpAuthenticationAndMethod:(NSString *)method
                                               andLocation:(NSString *)location
                                           andOptionalBody:(NSString *)optionalBody
                                            andLocalNumber:(NSString *)localNumber
                                               andPassword:(NSString *)password
                                                andCounter:(int64_t)counter;

+ (HttpRequest *)httpRequestFromData:(NSData *)data;
+ (HttpRequest *)httpRequestWithMethod:(NSString *)method
                           andLocation:(NSString *)location
                            andHeaders:(NSDictionary *)headers
                       andOptionalBody:(NSString *)optionalBody;

- (NSString *)toHttp;
- (NSData *)serialize;
- (NSString *)method;
- (NSString *)location;
- (NSString *)optionalBody;
- (NSDictionary *)headers;

- (bool)isEqualToHttpRequest:(HttpRequest *)other;

+ (NSString *)computeOtpAuthorizationTokenForLocalNumber:(NSString *)localNumber
                                         andCounterValue:(int64_t)counterValue
                                             andPassword:(NSString *)password;

+ (NSString *)computeBasicAuthorizationTokenForLocalNumber:(NSString *)localNumber andPassword:(NSString *)password;

@end
