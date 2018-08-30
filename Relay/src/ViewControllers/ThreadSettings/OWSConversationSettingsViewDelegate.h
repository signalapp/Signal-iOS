//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSGroupModel;

@protocol OWSConversationSettingsViewDelegate <NSObject>

- (void)conversationColorWasUpdated;
- (void)threadWasUpdated;

- (void)popAllConversationSettingsViews;

@end

NS_ASSUME_NONNULL_END
