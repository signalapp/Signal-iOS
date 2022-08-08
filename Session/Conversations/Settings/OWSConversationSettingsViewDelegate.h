//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSConversationSettingsViewController;
@class TSGroupModel;

@protocol OWSConversationSettingsViewDelegate <NSObject>

- (void)conversationSettingsDidRequestConversationSearch:(OWSConversationSettingsViewController *)conversationSettingsViewController;

@end

NS_ASSUME_NONNULL_END
