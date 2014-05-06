#import <Foundation/Foundation.h>
#import "Environment.h"
#import "DH3KKeyAgreementProtocol.h"
#import "EC25KeyAgreementProtocol.h"

@interface Release : NSObject

/// Connects to actual production infrastructure
+(Environment*) releaseEnvironmentWithLogging:(id<Logging>)logging;

/// Connects to external testing infrastructure
+(Environment*) pseudoEnvironmentWithLogging:(id<Logging>)logging;

// Connects to Whisper test infrastructure.
+(Environment*) releaseInteropEnvironmentWithLogging:(id<Logging>)logging;

/// Fake environment with no logging
+(Environment*) unitTestEnvironment:(NSArray*)testingAndLegacyOptions;

+(DH3KKeyAgreementProtocol*) supportedDH3KKeyAgreementProtocol;

@end
