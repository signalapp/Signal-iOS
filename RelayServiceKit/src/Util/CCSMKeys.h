//
//  CCSMKeys.h
//  Forsta
//
//  Created by Mark Descalzo on 6/25/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

#ifndef CCSMKeys_h
#define CCSMKeys_h

// Control message keys
#define FLControlMessageThreadUpdateKey @"threadUpdate"
#define FLControlMessageThreadClearKey @"threadClear"
#define FLControlMessageThreadCloseKey @"threadClose"
#define FLControlMessageThreadArchiveKey @"threadArchive"
#define FLControlMessageThreadRestoreKey @"threadRestore"
#define FLControlMessageThreadDeleteKey @"threadDelete"
#define FLControlMessageThreadSnoozeKey @"snooze"
#define FLControlMessageProvisionRequestKey @"provisionRequest"
#define FLControlMessageSyncRequestKey @"syncRequest"
#define FLControlMessageCallOfferKey @"callOffer"
#define FLControlMessageCallLeaveKey @"callLeave"
#define FLControlMessageCallICECandidates @"callICECandidates"

// Thread keys
#define FLThreadTitleKey @"threadTitle"
#define FLThreadIDKey @"threadId"
#define FLThreadTypeKey @"threadType"
#define FLDistributionKey @"distribution"
#define FLExpressionKey @"expression"
#define FLThreadTypeConversation @"conversation"
#define FLThreadTypeAnnouncement @"announcement"

// Message keys
#define FLMessageTypeContentKey @"content"
#define FLMessageTypePollKey @"poll"
#define FLMessageTypePollResponseKey @"pollResponse"
#define FLMessageTypeControlKey @"control"
#define FLMessageTypeReceiptKey @"receipt"

#endif /* CCSMKeys_h */
