#import "HttpRequestUtil.h"
#import "Constraints.h"
#import "PreferencesUtil.h"
#import "Util.h"
#import "SignalKeyingStorage.h"

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
                                                     andLocalNumber:SignalKeyingStorage.localNumber
                                                        andPassword:SignalKeyingStorage.serverAuthPassword];
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
                                                   andLocalNumber:SignalKeyingStorage.localNumber
                                                      andPassword:SignalKeyingStorage.serverAuthPassword
                                                       andCounter:[SignalKeyingStorage getAndIncrementOneTimeCounter]];
}
+(HttpRequest*)httpRequestUnauthenticatedWithMethod:(NSString*)method
                                        andLocation:(NSString*)location {
    return [HttpRequest httpRequestUnauthenticatedWithMethod:method
                                                 andLocation:location
                                             andOptionalBody:nil];
}

@end
