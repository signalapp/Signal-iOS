#import "HTTPRequest+Util.h"
#import "Constraints.h"
#import "PropertyListPreferences+Util.h"
#import "Util.h"
#import "SGNKeychainUtil.h"

@implementation HTTPRequest (Util)

- (instancetype)initWithBasicAuthenticationAndMethod:(NSString*)method
                                         andLocation:(NSString*)location {
    return [self initWithBasicAuthenticationAndMethod:method
                                          andLocation:location
                                      andOptionalBody:nil];
}

- (instancetype)initWithBasicAuthenticationAndMethod:(NSString*)method
                                         andLocation:(NSString*)location
                                     andOptionalBody:(NSString*)optionalBody {
    return [self initWithBasicAuthenticationAndMethod:method
                                          andLocation:location
                                      andOptionalBody:optionalBody
                                       andLocalNumber:SGNKeychainUtil.localNumber
                                          andPassword:SGNKeychainUtil.serverAuthPassword];
}

- (instancetype)initWithOTPAuthenticationAndMethod:(NSString*)method
                                       andLocation:(NSString*)location {
    return [self initWithOTPAuthenticationAndMethod:method
                                        andLocation:location
                                    andOptionalBody:nil];
}

- (instancetype)initWithOTPAuthenticationAndMethod:(NSString*)method
                                       andLocation:(NSString*)location
                                   andOptionalBody:(NSString*)optionalBody {
    return [self initWithOTPAuthenticationAndMethod:method
                                        andLocation:location
                                    andOptionalBody:optionalBody
                                     andLocalNumber:SGNKeychainUtil.localNumber
                                        andPassword:SGNKeychainUtil.serverAuthPassword
                                         andCounter:[SGNKeychainUtil getAndIncrementOneTimeCounter]];
}

- (instancetype)initUnauthenticatedWithMethod:(NSString*)method
                                  andLocation:(NSString*)location {
    return [self initUnauthenticatedWithMethod:method
                                   andLocation:location
                               andOptionalBody:nil];
}

@end
