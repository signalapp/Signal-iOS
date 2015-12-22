#import <Foundation/Foundation.h>
#import "DH3KKeyAgreementProtocol.h"
#import "EC25KeyAgreementProtocol.h"
#import "Environment.h"

@interface Release : NSObject

/// Connects to actual production infrastructure
+ (Environment *)releaseEnvironmentWithLogging:(id<Logging>)logging;

+ (Environment *)stagingEnvironmentWithLogging:(id<Logging>)logging;

/// Fake environment with no logging
+ (Environment *)unitTestEnvironment:(NSArray *)testingAndLegacyOptions;

+ (DH3KKeyAgreementProtocol *)supportedDH3KKeyAgreementProtocol;

@end
