#import <Foundation/Foundation.h>
#import "PhoneNumber.h"

@interface HTTPRequest : NSObject

@property (strong, nonatomic, readonly) NSString*     method;
@property (strong, nonatomic, readonly) NSString*     location;
@property (strong, nonatomic, readonly) NSString*     optionalBody;
@property (strong, nonatomic, readonly) NSDictionary* headers;

- (instancetype)initUnauthenticatedWithMethod:(NSString*)method
                                  andLocation:(NSString*)location
                              andOptionalBody:(NSString*)optionalBody;

- (instancetype)initWithBasicAuthenticationAndMethod:(NSString*)method
                                         andLocation:(NSString*)location
                                     andOptionalBody:(NSString*)optionalBody
                                      andLocalNumber:(PhoneNumber*)localNumber
                                         andPassword:(NSString*)password;

- (instancetype)initWithOTPAuthenticationAndMethod:(NSString*)method
                                       andLocation:(NSString*)location
                                   andOptionalBody:(NSString*)optionalBody
                                    andLocalNumber:(PhoneNumber*)localNumber
                                       andPassword:(NSString*)password
                                        andCounter:(int64_t)counter;

- (instancetype)initWithMethod:(NSString*)method
                   andLocation:(NSString*)location
                    andHeaders:(NSDictionary*)headers
               andOptionalBody:(NSString*)optionalBody;

- (instancetype)initFromData:(NSData*)data;

- (NSString*)toHTTP;
- (NSData*)serialize;

- (bool)isEqualToHTTPRequest:(HTTPRequest*)other;

+ (NSString*)computeOtpAuthorizationTokenForLocalNumber:(PhoneNumber*)localNumber
                                        andCounterValue:(int64_t)counterValue
                                            andPassword:(NSString*)password;

+ (NSString*)computeBasicAuthorizationTokenForLocalNumber:(PhoneNumber*)localNumber
                                              andPassword:(NSString*)password;

@end
