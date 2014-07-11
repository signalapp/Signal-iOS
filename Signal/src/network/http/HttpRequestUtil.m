#import "HttpRequestUtil.h"
#import "Constraints.h"
#import "PreferencesUtil.h"
#import "Util.h"
#import "SGNKeychainUtil.h"

@implementation HttpRequest (HttpRequestUtil)

+(HttpRequest*)httpRequestWithBasicAuthenticationAndMethod:(NSString*)method
                                               andLocation:(NSString*)location {
    return [HttpRequest httpRequestWithBasicAuthenticationAndMethod:method
                                                        andLocation:location
                                                    andOptionalBody:nil];
}
+(HttpRequest*)httpRequestWithBasicAuthenticationAndMethod:(NSString*)method
                                               andLocation:(NSString*)location
                                           andOptionalBody:(NSString*)optionalBody {
    return [HttpRequest httpRequestWithBasicAuthenticationAndMethod:method
                                                        andLocation:location
                                                    andOptionalBody:optionalBody
                                                     andLocalNumber:[SGNKeychainUtil localNumber]
                                                        andPassword:[SGNKeychainUtil serverAuthPassword]];
}
+(HttpRequest*)httpRequestWithOtpAuthenticationAndMethod:(NSString*)method
                                             andLocation:(NSString*)location {
    return [HttpRequest httpRequestWithOtpAuthenticationAndMethod:method
                                                      andLocation:location
                                                  andOptionalBody:nil];
}
+(HttpRequest*)httpRequestWithOtpAuthenticationAndMethod:(NSString*)method
                                             andLocation:(NSString*)location
                                         andOptionalBody:(NSString*)optionalBody {
    return [HttpRequest httpRequestWithOtpAuthenticationAndMethod:method
                                                      andLocation:location
                                                  andOptionalBody:optionalBody
                                                   andLocalNumber:[SGNKeychainUtil localNumber]
                                                      andPassword:[SGNKeychainUtil serverAuthPassword]
                                                       andCounter:[SGNKeychainUtil getAndIncrementOneTimeCounter]];
}
+(HttpRequest*)httpRequestUnauthenticatedWithMethod:(NSString*)method
                                        andLocation:(NSString*)location {
    return [HttpRequest httpRequestUnauthenticatedWithMethod:method
                                                 andLocation:location
                                             andOptionalBody:nil];
}

@end
