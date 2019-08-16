//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface BaseModel : TSYapDatabaseObject

@property (class, nonatomic, readonly) BOOL shouldBeIndexedForFTS;

@end

NS_ASSUME_NONNULL_END
