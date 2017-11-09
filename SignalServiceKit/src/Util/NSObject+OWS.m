//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSObject+OWS.h"
#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSObject (OWS)

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end

NS_ASSUME_NONNULL_END
