//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// This header exposes private properties for SDS serialization.

@interface TSThread ()

@property (nonatomic, nullable, readonly) NSNumber *archivedAsOfMessageSortId;
@property (nonatomic, copy, nullable, readonly) NSString *messageDraft;

@property (nonatomic, nullable, readonly) NSDate *lastMessageDate DEPRECATED_ATTRIBUTE;
@property (nonatomic, nullable, readonly) NSDate *archivalDate DEPRECATED_ATTRIBUTE;

@end

NS_ASSUME_NONNULL_END
