#import "HttpRequestUtil.h"
#import "Constraints.h"
#import "KeyChainStorage.h"
#import "PreferencesUtil.h"
#import "Util.h"

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
                                                     andLocalNumber:[KeyChainStorage forceGetLocalNumber]
                                                        andPassword:[KeyChainStorage getOrGenerateSavedPassword]];
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
                                                   andLocalNumber:[KeyChainStorage forceGetLocalNumber]
                                                      andPassword:[KeyChainStorage getOrGenerateSavedPassword]
                                                       andCounter:[[[Environment getCurrent] preferences] getAndIncrementOneTimeCounter]];
}
+(HttpRequest*)httpRequestUnauthenticatedWithMethod:(NSString*)method
                                        andLocation:(NSString*)location {
    return [HttpRequest httpRequestUnauthenticatedWithMethod:method
                                                 andLocation:location
                                             andOptionalBody:nil];
}

@end
