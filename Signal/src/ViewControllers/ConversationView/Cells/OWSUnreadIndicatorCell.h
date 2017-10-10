//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewCell.h"

NS_ASSUME_NONNULL_BEGIN

@class TSUnreadIndicatorInteraction;

@interface OWSUnreadIndicatorCell : ConversationViewCell

//- (CGSize)bubbleSizeForInteraction:(TSUnreadIndicatorInteraction *)interaction
//               collectionViewWidth:(CGFloat)collectionViewWidth;

+ (NSString *)cellReuseIdentifier;

@end

NS_ASSUME_NONNULL_END
