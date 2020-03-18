//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSConversationSettingsViewController;
@class TSGroupThread;

@protocol OWSConversationSettingsViewDelegate <NSObject>

- (void)conversationColorWasUpdated;

- (void)conversationSettingsDidUpdateGroupThread:(TSGroupThread *)thread;

- (void)conversationSettingsDidRequestConversationSearch;

- (void)popAllConversationSettingsViewsWithCompletion:(void (^_Nullable)(void))completionBlock;

@end

NS_ASSUME_NONNULL_END
