//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ConditionLogger.h"
#import "Logging.h"

@interface DiscardingLog : NSObject <Logging, OccurrenceLogger, ConditionLogger, ValueLogger>
+ (DiscardingLog *)discardingLog;
@end
