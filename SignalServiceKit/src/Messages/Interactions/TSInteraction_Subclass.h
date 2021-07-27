//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSInteraction.h"

@interface TSInteraction (Subclass)

// Timestamps are *almost* always immutable. The one exception is for placeholder interactions.
// After a certain amount of time, a placeholder becomes ineligible for replacement. The would-be
// replacement is just inserted natively.
//
// This breaks all sorts of assumptions we have of timestamps being unique. To workaround this,
// we decrement the timestamp on a failed placeholder. This ensures that both the placeholder
// error message and the would-be replacement can coexist.
@property (nonatomic, assign) uint64_t timestamp;

@end
