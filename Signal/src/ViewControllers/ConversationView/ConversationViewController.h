//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewController;

typedef NS_CLOSED_ENUM(NSUInteger, ConversationViewAction) {
    ConversationViewActionNone,
    ConversationViewActionCompose,
    ConversationViewActionAudioCall,
    ConversationViewActionVideoCall,
    ConversationViewActionGroupCallLobby,
    ConversationViewActionNewGroupActionSheet,
    ConversationViewActionUpdateDraft
};

void CVCReloadCollectionViewForReset(ConversationViewController *cvc);

typedef void (^CVCPerformBatchUpdatesBlock)(void);
typedef void (^CVCPerformBatchUpdatesCompletion)(BOOL);
typedef void (^CVCPerformBatchUpdatesFailure)(void);

void CVCPerformBatchUpdates(ConversationViewController *cvc,
                            CVCPerformBatchUpdatesBlock batchUpdates,
                            CVCPerformBatchUpdatesCompletion completion,
                            CVCPerformBatchUpdatesFailure logFailureBlock,
                            BOOL shouldAnimateUpdates,
                            BOOL isLoadAdjacent);

NS_ASSUME_NONNULL_END
