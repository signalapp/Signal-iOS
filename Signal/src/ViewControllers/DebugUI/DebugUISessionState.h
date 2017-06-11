//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSContactThread;
@class OWSTableSection;

@interface DebugUISessionState : NSObject

+ (OWSTableSection *)sectionForContactThread:(TSContactThread *)contactThread;

@end

NS_ASSUME_NONNULL_END
