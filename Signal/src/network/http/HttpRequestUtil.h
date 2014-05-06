#import <Foundation/Foundation.h>
#import "HttpRequest.h"
#import "HttpResponse.h"
#import "Environment.h"

@interface HttpRequest (HttpRequestUtil)

+(HttpRequest*)httpRequestWithBasicAuthenticationAndMethod:(NSString*)method
                                               andLocation:(NSString*)location;
+(HttpRequest*)httpRequestWithBasicAuthenticationAndMethod:(NSString*)method
                                               andLocation:(NSString*)location
                                           andOptionalBody:(NSString*)optionalBody;
+(HttpRequest*)httpRequestWithOtpAuthenticationAndMethod:(NSString*)method
                                             andLocation:(NSString*)location;
+(HttpRequest*)httpRequestUnauthenticatedWithMethod:(NSString*)method
                                        andLocation:(NSString*)location;

@end
