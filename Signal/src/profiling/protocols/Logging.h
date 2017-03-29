//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ConditionLogger.h"
#import "OccurrenceLogger.h"
#import "ValueLogger.h"

@protocol Logging <NSObject>

/// Note: the logger MUST NOT store a reference to the given sender. Calling this method, or storing its result, must
/// not create a reference cycle.
- (id<OccurrenceLogger>)getOccurrenceLoggerForSender:(id)sender withKey:(NSString *)key;

/// Note: the logger MUST NOT store a reference to the given sender. Calling this method, or storing its result, must
/// not create a reference cycle.
- (id<ConditionLogger>)getConditionLoggerForSender:(id)sender;

/// Note: the logger MUST NOT store a reference to the given sender. Calling this method, or storing its result, must
/// not create a reference cycle.
- (id<ValueLogger>)getValueLoggerForValue:(id)valueIdentity from:(id)sender;

@end
