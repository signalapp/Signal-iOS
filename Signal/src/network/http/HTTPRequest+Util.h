#import <Foundation/Foundation.h>
#import "HTTPRequest.h"
#import "HTTPResponse.h"
#import "Environment.h"

@interface HTTPRequest (Util)

- (instancetype)initWithBasicAuthenticationAndMethod:(NSString*)method
                                         andLocation:(NSString*)location;
- (instancetype)initWithBasicAuthenticationAndMethod:(NSString*)method
                                         andLocation:(NSString*)location
                                     andOptionalBody:(NSString*)optionalBody;
- (instancetype)initWithOTPAuthenticationAndMethod:(NSString*)method
                                       andLocation:(NSString*)location;
- (instancetype)initUnauthenticatedWithMethod:(NSString*)method
                                  andLocation:(NSString*)location;

@end
