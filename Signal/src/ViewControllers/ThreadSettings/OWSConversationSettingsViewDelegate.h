//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSConversationSettingsViewController;
@class SignalServiceAddress;
@class TSGroupModel;

@protocol OWSConversationSettingsViewDelegate <NSObject>

- (void)conversationColorWasUpdated;

- (void)conversationSettingsDidUpdateGroupWithId:(NSData *)groupId
                                         members:(NSArray<SignalServiceAddress *> *)members
                                  administrators:(NSArray<SignalServiceAddress *> *)administrators
                                            name:(nullable NSString *)name
                                      avatarData:(nullable NSData *)avatarData;

- (void)conversationSettingsDidRequestConversationSearch:(OWSConversationSettingsViewController *)conversationSettingsViewController;

- (void)popAllConversationSettingsViewsWithCompletion:(void (^_Nullable)(void))completionBlock;

@end

NS_ASSUME_NONNULL_END
