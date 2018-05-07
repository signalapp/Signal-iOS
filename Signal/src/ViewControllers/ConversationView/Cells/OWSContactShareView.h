//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ContactShareViewModel;
@class OWSContact;
@class OWSContactsManager;

@protocol OWSContactShareViewDelegate <NSObject>

- (void)sendMessageToContactShare:(ContactShareViewModel *)contactShare;
- (void)sendInviteToContactShare:(ContactShareViewModel *)contactShare;
- (void)showAddToContactUIForContactShare:(ContactShareViewModel *)contactShare;

@end

#pragma mark -

@interface OWSContactShareView : UIView

- (instancetype)initWithContactShare:(ContactShareViewModel *)contactShare
                          isIncoming:(BOOL)isIncoming
                            delegate:(id<OWSContactShareViewDelegate>)delegate;

- (void)createContents;

+ (CGFloat)bubbleHeightForContactShare:(ContactShareViewModel *)contactShare;

// Returns YES IFF the tap was handled.
- (BOOL)handleTapGesture:(UITapGestureRecognizer *)sender;

@end

NS_ASSUME_NONNULL_END
