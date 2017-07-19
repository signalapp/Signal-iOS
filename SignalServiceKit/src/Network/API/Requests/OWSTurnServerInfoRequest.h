//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Fetch a list of viable ICE candidates (including TURN and STUN) used for the WebRTC call signaling process.
 */
NS_SWIFT_NAME(TurnServerInfoRequest)
@interface OWSTurnServerInfoRequest : TSRequest

@end

NS_ASSUME_NONNULL_END
