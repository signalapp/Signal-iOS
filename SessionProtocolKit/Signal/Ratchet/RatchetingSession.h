//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@class AliceAxolotlParameters;
@class BobAxolotlParameters;
@class ECKeyPair;
@class SessionState;

@interface RatchetingSession : NSObject

+ (void)throws_initializeSession:(SessionState *)session
                  sessionVersion:(int)sessionVersion
                 AliceParameters:(AliceAxolotlParameters *)parameters NS_SWIFT_UNAVAILABLE("throws objc exceptions");

+ (BOOL)initializeSession:(SessionState *)session
           sessionVersion:(int)sessionVersion
          aliceParameters:(AliceAxolotlParameters *)aliceParameters
                    error:(NSError **)outError;

+ (void)throws_initializeSession:(SessionState *)session
                  sessionVersion:(int)sessionVersion
                   BobParameters:(BobAxolotlParameters *)parameters NS_SWIFT_UNAVAILABLE("throws objc exceptions");

+ (BOOL)initializeSession:(SessionState *)session
           sessionVersion:(int)sessionVersion
            bobParameters:(BobAxolotlParameters *)bobParameters
                    error:(NSError **)outError;

/**
 *  For testing purposes
 */

+ (void)throws_initializeSession:(SessionState *)session
                  sessionVersion:(int)sessionVersion
                 AliceParameters:(AliceAxolotlParameters *)parameters
                   senderRatchet:(ECKeyPair *)ratchet NS_SWIFT_UNAVAILABLE("throws objc exceptions");

@end
