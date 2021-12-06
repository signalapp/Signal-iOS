//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

#if DEBUG

public extension DebugUIScreenshots {

    @objc
    class func deleteAllThreads() {
        databaseStorage.write { transaction in
            TSInteraction.anyRemoveAllWithoutInstantation(transaction: transaction)
            TSAttachment.anyRemoveAllWithoutInstantation(transaction: transaction)
            TSThread.anyRemoveAllWithoutInstantation(transaction: transaction)
        }
    }

    @objc
    class func makeThreadsForScreenshots() {

        // Get the address of the local user.
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return
        }

        databaseStorage.asyncWrite { transaction in

            // Time to start
            // Modify the macOS system clock to "set" this to a specific time
            let startingDateMS = Date.ows_millisecondTimestamp()

            // Localizing content:
            //
            // 1. Add NS_LocalizedString() (remove '_' like below).
            //    Make sure the "key" (e.g. SCREENSHOT_USERNAME_1) is unique for each string.
            //    Make sure you add a comment for the translators.
            //
            // someString1 will always be "Alice."
            // let someString1 = "Alice"
            // someLocalizedString might be "Alice" in English and "Boris" in Russian,
            // depending on your device/simulator's locale's language.
            // let someLocalizedString = NSLocalizedString("SCREENSHOT_USERNAME_1", comment: "An example name for a user we use in the screenshots.")
            // 2. Run the l10n string script in the terminal
            //    Scripts/translation/auto-genstrings
            //    This will make sure there's an entry in the _English_ localization for each key in the source.
            // 3. Search for the key you just added - you'll find it in the English localization file.
            //    Add a English value.
            // 4. The strings for the other languages won't be set until you sync your l10n strings.
            //    DON'T DO THIS without checking with the engineers.
            //    It can cause leave Transifex in the wrong state.
            //    It is done with this script:
            //    Scripts/translation/sync-translations

            // If you add more users, make sure they each have
            // unique numbers and uuid strings.
            // TODOs set local profile phone number per locale
            self.setLocalProfile(givenName: NSLocalizedString("SCREENSHOT_NAME_LOCAL_PROFILE",
                                                              comment: "This appears in Signal > Settings. A female leadership/presidential/chairwoman position + female name Freyja or similar spelling. This will have a cat profile photo."),
                                 familyName: "",
                                 avatarBundleFilename: "address-chairwoman-freya.jpg")
            let address1 = self.ensureAccount(phoneNumber: "+13213214301",
                                              uuidString: "123e4567-e89b-12d3-a456-426655440001",
                                              // Example usage of NS_LocalizedString().
                                              // givenName: NSLocalizedString("SCREENSHOT_USERNAME_1", comment: "An example name for a user we use in the screenshots."),
                                              givenName: NSLocalizedString("SCREENSHOT_NAME_CONTACT_ONE",
                                                                           comment: "This is a contact's name. A male leadership/presidential position + the sound a cat makes. This will have a cat profile photo."),
                                              familyName: "",
                                              avatarBundleFilename: "address-chairman-meow.jpg",
                                              transaction: transaction)
            let address2 = self.ensureAccount(phoneNumber: "+13213214302",
                                              uuidString: "123e4567-e89b-12d3-a456-426655440002",
                                              givenName: NSLocalizedString("SCREENSHOT_NAME_CONTACT_TWO",
                                                                           comment: "This is a contact's name. Replace the name for a more common name in your locale if this sounds too foreign. This should be a unique non-public figure's name. This profile photo will be either male or female."),
                                              familyName: "",
                                              avatarBundleFilename: "address-male-1.jpg",
                                              transaction: transaction)
            let address3 = self.ensureAccount(phoneNumber: "+13213214303",
                                              uuidString: "123e4567-e89b-12d3-a456-426655440003",
                                              givenName: NSLocalizedString("SCREENSHOT_NAME_CONTACT_THREE",
                                                                           comment: "This is a contact's name. Please keep a similar nickname for Nikola/Nikita/etc in your language and only post the last initial. This profile photo will be either male or female but mostly female."),
                                              familyName: "",
                                              avatarBundleFilename: "address-female-9.jpg",
                                              transaction: transaction)
            let address4 = self.ensureAccount(phoneNumber: "+13213214304",
                                              uuidString: "123e4567-e89b-12d3-a456-426655440004",
                                              givenName: NSLocalizedString("SCREENSHOT_NAME_CONTACT_FOUR",
                                                                           comment: "This is a contact's name. Replace the name for a more common name in your locale if this sounds too foreign. This should be a unique non-public figure's name. This profile photo will be either male or female. Choose a unisex name if possible."),
                                              familyName: "",
                                              avatarBundleFilename: "address-female-12.jpg",
                                              transaction: transaction)
            let address5 = self.ensureAccount(phoneNumber: "+13213214305",
                                              uuidString: "123e4567-e89b-12d3-a456-426655440005",
                                              // givenName: "Ali Smith",
                                              givenName: NSLocalizedString("SCREENSHOT_NAME_CONTACT_FIVE",
                                                                           comment: "This is a contact's name. Please keep the nick name Ali and change the last name to a popular lastname in your language. This will have male profile photo."),
                                              familyName: "",
                                              avatarBundleFilename: "address-male-4.jpg",
                                              transaction: transaction)
            let address6 = self.ensureAccount(phoneNumber: "+13213214306",
                                              uuidString: "123e4567-e89b-12d3-a456-426655440006",
                                              givenName: NSLocalizedString("SCREENSHOT_NAME_CONTACT_SIX",
                                                                           comment: "This is a contact's name. Replace the name for a more common name in your locale if this sounds too foreign. This will have a male profile photo."),
                                              familyName: "",
                                              avatarBundleFilename: "address-male-3.jpg",
                                              transaction: transaction)
            let address7 = self.ensureAccount(phoneNumber: "+13213214307",
                                              uuidString: "123e4567-e89b-12d3-a456-426655440007",
                                              givenName: NSLocalizedString("SCREENSHOT_NAME_CONTACT_SEVEN",
                                                                           comment: "This is a contact's name. Please keep a similar unisex first name (Kai) if this name isn't common and only post the last initial. This will have a female profile photo."),
                                              familyName: "",
                                              avatarBundleFilename: "address-female-1.jpg",
                                              transaction: transaction)
            let address8 = self.ensureAccount(phoneNumber: "+13213214308",
                                              uuidString: "123e4567-e89b-12d3-a456-426655440008",
                                              givenName: NSLocalizedString("SCREENSHOT_NAME_CONTACT_EIGHT",
                                                                           comment: "This is a contact's name. Replace the name for a more common name in your locale if this sounds too foreign. This should be a unique non-public figure's name. This will have a female profile photo."),
                                              familyName: "",
                                              avatarBundleFilename: "address-female-2.jpg",
                                              transaction: transaction)
            let address9 = self.ensureAccount(phoneNumber: "+13213214309",
                                              uuidString: "123e4567-e89b-12d3-a456-426655440009",
                                              givenName: NSLocalizedString("SCREENSHOT_NAME_CONTACT_NINE",
                                                                           comment: "This is a contact's name. Replace the name for a more common name in your locale if this sounds too foreign. Include two last names if that is represented in your locale. This should be a unique non-public figure's name. This will have a female profile photo."),
                                              familyName: "",
                                              avatarBundleFilename: "address-female-7.jpg",
                                              transaction: transaction)
            let address10 = self.ensureAccount(phoneNumber: "+13213214310",
                                              uuidString: "123e4567-e89b-12d3-a456-426655440010",
                                              givenName: NSLocalizedString("SCREENSHOT_NAME_CONTACT_TEN",
                                                                           comment: "This is a contact's name. Replace the name for a more common name in your locale if this sounds too foreign. This should be a unique non-public figure's name. This will have a female profile photo."),
                                              familyName: "",
                                              avatarBundleFilename: "address-female-8.jpg",
                                              transaction: transaction)

            // 1:1 website screenshot for thread
            if true {
                let otherAddress = address10
                let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
                let timestampMessage0 = startingDateMS - (6 * kDayInMs + 55 * kMinuteInMs)
                let attachmentMessage0 = buildAttachment(bundleFilename: "nature-5-cat.jpg",
                                                         mimeType: OWSMimeTypeImageJpeg,
                                                         transaction: transaction)
                let attachmentMessage1 = buildAttachment(bundleFilename: "nature-7-cat.jpg",
                                                         mimeType: OWSMimeTypeImageJpeg,
                                                         transaction: transaction)
                let attachmentMessage2 = buildAttachment(bundleFilename: "nature-6-cat.jpg",
                                                         mimeType: OWSMimeTypeImageJpeg,
                                                         transaction: transaction)
                let message0 = self.buildOutgoingMessage(thread: thread,
                                                         messageBody: nil,
                                                         timestamp: timestampMessage0,
                                                         attachments: [attachmentMessage0, attachmentMessage1, attachmentMessage2],
                                                         transaction: transaction)
                _ = message0.recordReaction(for: otherAddress,
                                                       emoji: "❤️",
                                                       sentAtTimestamp: Date.ows_millisecondTimestamp(),
                                                       receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                       transaction: transaction)
                let timestampMessage1 = startingDateMS - (6 * kDayInMs + 30 * kMinuteInMs)
                let message1 = self.buildIncomingMessage(thread: thread, authorAddress: otherAddress,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_DIRECT_ONE_MESSAGE_ONE",
                                                                                        comment: "This is a message."),
                                                         timestamp: timestampMessage1, transaction: transaction)
                message1.debugonly_markAsReadNow(transaction: transaction)
                _ = message1.recordReaction(for: localAddress,
                                                     emoji: "👍",
                                                     sentAtTimestamp: Date.ows_millisecondTimestamp(),
                                                     receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                     transaction: transaction)
                let timestampMessage2 = startingDateMS - (6 * kDayInMs + 3 * kMinuteInMs)
                let message2 = self.buildOutgoingMessage(thread: thread, messageBody: "☺️",
                                                         timestamp: timestampMessage2, transaction: transaction)
                message2.update(withReadRecipient: otherAddress, recipientDeviceId: 0, readTimestamp: Date.ows_millisecondTimestamp(), transaction: transaction)
                let timestampMessage3 = startingDateMS - (6 * kDayInMs + 3 * kMinuteInMs)
                let message3 = self.buildOutgoingMessage(thread: thread, messageBody: NSLocalizedString("SCREENSHOT_THREAD_DIRECT_ONE_MESSAGE_TWO",
                                                                                                        comment: "This is a message."),
                                                         timestamp: timestampMessage3, transaction: transaction)
                message3.update(withReadRecipient: otherAddress, recipientDeviceId: 0, readTimestamp: Date.ows_millisecondTimestamp(), transaction: transaction)
                let timestampMessage4 = startingDateMS - (6 * kDayInMs + 3 * kMinuteInMs)
                let message4 = self.buildOutgoingMessage(thread: thread,
                                                         messageBody: nil,
                                                         timestamp: timestampMessage4, transaction: transaction)
                // Q: Which pack? A: Bandit the Cat.
                let packIdHex = "9acc9e8aba563d26a4994e69263e3b25"
                let packKeyHex = "5a6dff3948c28efb9b7aaf93ecc375c69fc316e78077ed26867a14d10a0f6a12"
                // Which sticker - the index in the pack.
                let stickerId0: UInt32 = 4
                if let messageSticker = self.buildMessageSticker(packIdHex: packIdHex,
                                                                 packKeyHex: packKeyHex,
                                                                 stickerId: stickerId0,
                                                                 transaction: transaction) {
                    message4.update(with: messageSticker, transaction: transaction)
                }
            }

            // 1:1 encryption animation for website
            if true {
                let otherAddress = address4
                let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
                let timestampMessage1 = startingDateMS - (5 * kDayInMs + 12 * kHourInMs)
                let message1 = self.buildIncomingMessage(thread: thread, authorAddress: otherAddress,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_DIRECT_TWO_MESSAGE_ONE",
                                                                                        comment: "This is a message before an image of mountains + a lake."),
                                                         timestamp: timestampMessage1, transaction: transaction)
                message1.debugonly_markAsReadNow(transaction: transaction)
                let timestampMessage2 = startingDateMS - (5 * kDayInMs + 12 * kHourInMs)
                let attachmentMessage2 = buildAttachment(bundleFilename: "nature-8-NewZealand.jpg",
                                                         mimeType: OWSMimeTypeImageJpeg,
                                                         transaction: transaction)
                let message2 = self.buildIncomingMessage(thread: thread, authorAddress: otherAddress,
                                                         messageBody: nil,
                                                         timestamp: timestampMessage2,
                                                         attachments: [attachmentMessage2], transaction: transaction)
                message2.debugonly_markAsReadNow(transaction: transaction)
                let timestampMessage3 = startingDateMS - (5 * kDayInMs + 12 * kHourInMs)
                let message3 = self.buildOutgoingMessage(thread: thread,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_DIRECT_TWO_MESSAGE_TWO",
                                                                                        comment: "This is a message after an image of mountains + a lake."),
                                                         timestamp: timestampMessage3,
                                                         transaction: transaction)
                message3.update(withReadRecipient: otherAddress, recipientDeviceId: 0, readTimestamp: Date.ows_millisecondTimestamp(), transaction: transaction)
                let timestampMessage4 = startingDateMS - (5 * kDayInMs + 12 * kHourInMs)
                let message4 = self.buildIncomingMessage(thread: thread, authorAddress: otherAddress,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_DIRECT_TWO_MESSAGE_THREE",
                                                                                        comment: "This is a message."),
                                                         timestamp: timestampMessage4, transaction: transaction)
                message4.debugonly_markAsReadNow(transaction: transaction)
            }

            // 1:1 outgoing
            if true {
                let otherAddress = address9
                let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
                let timestampMessage1 = startingDateMS - (4 * kDayInMs)
                let message1 = self.buildOutgoingMessage(thread: thread, messageBody: "🤣🤣🤣",
                                                         timestamp: timestampMessage1, transaction: transaction)
                message1.update(withReadRecipient: otherAddress, recipientDeviceId: 0, readTimestamp: Date.ows_millisecondTimestamp(), transaction: transaction)
            }

             // 1:1 incoming sticker
             if true {
                 let otherAddress = address6
                 let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
                 let timestampMessage1 = startingDateMS - (3 * kDayInMs + 12 * kHourInMs)
                 let message1 = self.buildIncomingMessage(thread: thread, authorAddress: otherAddress,
                                                          messageBody: NSLocalizedString("SCREENSHOT_THREAD_DIRECT_THREE_MESSAGE_ONE",
                                                                                         comment: "Replace crepes with similar item that you bake or cook i.e. bread, croissants, naan."),
                                                          timestamp: timestampMessage1, transaction: transaction)
                 message1.debugonly_markAsReadNow(transaction: transaction)
             }

            // Group sent attachment
            if true {
                let memberAddresses = [
                    address8,
                    address9
                ]

                // avatarData should be PNG data.
                let thread = try! GroupManager.createGroupForTests(members: memberAddresses,
                                                                   name: NSLocalizedString("SCREENSHOT_NAME_GROUP_ONE",
                                                                                           comment: "This is for a group of people interested in discussing books they've read."),
                                                                   avatarData: buildAvatarData(bundleFilename: "address-group-book.jpg"),
                                                                   transaction: transaction)

                buildOutgoingMessage(
                    thread: thread,
                    messageBody: NSLocalizedString(
                        "SCREENSHOT_THREAD_GROUP_ONE_MESSAGE_ONE",
                        comment: "This is for a message in the 'Book Club' group chat"),
                    timestamp: startingDateMS - (3 * kDayInMs + 4 * kHourInMs),
                    transaction: transaction)

                let attachmentMessage2 = buildAttachment(
                    bundleFilename: "1984.txt",
                    mimeType: "text/plain",
                    sourceFilename: NSLocalizedString(
                        "SCREENSHOT_THREAD_GROUP_ONE_FILE_NAME",
                        comment: "1984 is the book title. The file extension is a text file."),
                    transaction: transaction)

                buildOutgoingMessage(
                    thread: thread,
                    messageBody: nil,
                    timestamp: startingDateMS - (3 * kDayInMs + 4 * kMinuteInMs),
                    attachments: [attachmentMessage2],
                    transaction: transaction)
            }

            // Group incoming attachment + caption
            if true {
                let memberAddresses = [
                    address8,
                    address9
                ]

                // avatarData should be PNG data.
                let thread = try! GroupManager.createGroupForTests(members: memberAddresses,
                                                                   name: NSLocalizedString("SCREENSHOT_NAME_GROUP_TWO",
                                                                                           comment: "This is for a group chat for people who want weather updates."),
                                                                   avatarData: buildAvatarData(bundleFilename: "nature-2-trees.JPG"),
                                                                   transaction: transaction)

                buildOutgoingMessage(
                    thread: thread,
                    messageBody: NSLocalizedString(
                        "SCREENSHOT_THREAD_GROUP_TWO_MESSAGE_ONE",
                        comment: "This is a message. Please include the emoji if possible."),
                    timestamp: startingDateMS - (2 * kDayInMs + 8 * kHourInMs),
                    transaction: transaction)

                let attachmentMessage2 = buildAttachment(
                    bundleFilename: "test-jpg-2.JPG",
                    mimeType: OWSMimeTypeImageJpeg,
                    transaction: transaction)

                let message2 = buildIncomingMessage(
                    thread: thread,
                    authorAddress: address9,
                    messageBody: NSLocalizedString(
                        "SCREENSHOT_THREAD_GROUP_TWO_MESSAGE_TWO",
                        comment: "This is a message sent with an attachment."),
                    timestamp: startingDateMS - (2 * kDayInMs + 8 * kHourInMs + 1 * kMinuteInMs),
                    attachments: [attachmentMessage2],
                    transaction: transaction)

                message2.debugonly_markAsReadNow(transaction: transaction)
            }

            // 1:1 received text
            if true {
                let otherAddress = address3
                let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
                let message1 = self.buildOutgoingMessage(thread: thread, messageBody: NSLocalizedString("SCREENSHOT_THREAD_DIRECT_FOUR_MESSAGE_ONE",
                                                                                                        comment: "This is a message."),
                                                         transaction: transaction)
                // This marks the outgoing message as read
                // as opposed to displaying one sent check mark
                message1.update(withReadRecipient: otherAddress, recipientDeviceId: 0, readTimestamp: Date.ows_millisecondTimestamp(), transaction: transaction)
                let timestampMessage2 = startingDateMS - (2 * kDayInMs + 4 * kHourInMs + 42 * kMinuteInMs)
                let message2 = self.buildIncomingMessage(thread: thread,
                                                         authorAddress: otherAddress,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_DIRECT_FOUR_MESSAGE_TWO",
                                                                                        comment: "This is a message. Include 'Thanks' + a similar phrase with the :) emoji."),
                                                         timestamp: timestampMessage2, transaction: transaction)
                // This marks the incoming message as read
                // so the "New Messages" indicator/ "Today" is not displayed
                message2.debugonly_markAsReadNow(transaction: transaction)
            }

            // Group received text
            if true {
                let memberAddresses = [
                    address6,
                    address7
                ]

                // avatarData should be PNG data.
                let thread = try! GroupManager.createGroupForTests(members: memberAddresses,
                                                                   name: NSLocalizedString("SCREENSHOT_NAME_GROUP_THREE",
                                                                                           comment: "Please include emoji. This is a group name for people who climb rocks/climb trees/hike mountains/outside mountaineering."),
                                                                   avatarData: buildAvatarData(bundleFilename: "address-group-climbers.jpg"),
                                                                   transaction: transaction)
                let timestampMessage1 = startingDateMS - (2 * kDayInMs + 2 * kHourInMs)
                let message1 = self.buildIncomingMessage(thread: thread, authorAddress: address6,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_GROUP_THREE_MESSAGE_ONE",
                                                                                        comment: "This is a message in the 'Rock Climbers' group chat. Please translate to make sense for the translated group name. For example: Which way should we go?"),
                                                         timestamp: timestampMessage1, transaction: transaction)
                message1.debugonly_markAsReadNow(transaction: transaction)
            }

            // Group received
            if true {
                let memberAddresses = [
                    address4,
                    address5
                ]

                // avatarData should be PNG data.
                let thread = try! GroupManager.createGroupForTests(members: memberAddresses,
                                                                   name: NSLocalizedString("SCREENSHOT_NAME_GROUP_FOUR",
                                                                                           comment: "Please include emoji. This is a group name/channel name for pictures of the sun in the sky."),
                                                                   avatarData: buildAvatarData(bundleFilename: "nature-4-sunset.jpg"),
                                                                   transaction: transaction)

                buildOutgoingMessage(
                    thread: thread,
                    messageBody: NSLocalizedString(
                        "SCREENSHOT_THREAD_GROUP_FOUR_MESSAGE_ONE",
                        comment: "This is a message in the Sunsets group chat."),
                    timestamp: startingDateMS - (1 * kDayInMs + 18 * kHourInMs),
                    transaction: transaction)

                let attachmentMessage2 = buildAttachment(
                    bundleFilename: "nature-3-road.JPG",
                    mimeType: OWSMimeTypeImageJpeg,
                    transaction: transaction)

                buildOutgoingMessage(
                    thread: thread,
                    messageBody: nil,
                    timestamp: startingDateMS - (1 * kDayInMs + 18 * kHourInMs + 10 * kMinuteInMs),
                    attachments: [attachmentMessage2],
                    isViewOnceMessage: true,
                    transaction: transaction)
            }

            // Example of how to make a simple 1:1 thread.
            // TODO check voice note format
            if true {
                let otherAddress = address7
                let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
                let timestampMessage1 = startingDateMS - (9 * kHourInMs)
                let attachmentMessage1 = buildAttachment(bundleFilename: "test-jpg-3.JPG",
                                                         mimeType: OWSMimeTypeImageJpeg,
                                                         transaction: transaction)

                buildOutgoingMessage(
                    thread: thread,
                    messageBody: nil,
                    timestamp: timestampMessage1,
                    attachments: [attachmentMessage1],
                    transaction: transaction)

                buildOutgoingMessage(
                    thread: thread,
                    messageBody: NSLocalizedString(
                        "SCREENSHOT_THREAD_DIRECT_FIVE_MESSAGE_ONE",
                        comment: "This is a message expressing support/happiness/awe/shock."),
                    timestamp: startingDateMS - (8 * kHourInMs + 27 * kMinuteInMs),
                    transaction: transaction)

                GroupManager.remoteUpdateDisappearingMessages(withContactOrV1GroupThread: thread,
                                                              disappearingMessageToken: DisappearingMessageToken(isEnabled: true, durationSeconds: UInt32(24 * kHourInterval)),
                                                              groupUpdateSourceAddress: localAddress,
                                                              transaction: transaction)
                let attachmentMessage3 = buildAttachment(bundleFilename: "sonarping.mp3",
                                                         mimeType: "audio/mp3",
                                                         transaction: transaction)
                attachmentMessage3.attachmentType = .voiceMessage
                attachmentMessage3.anyOverwritingUpdate(transaction: transaction)
                let timestampMessage3 = startingDateMS - (3 * kHourInMs + 58 * kMinuteInMs)
                let message3 = self.buildOutgoingMessage(thread: thread,
                                                         messageBody: nil,
                                                         timestamp: timestampMessage3,
                                                         attachments: [attachmentMessage3],
                                                         expiresInSeconds: 10800,
                                                         transaction: transaction)
                _ = message3.recordReaction(for: otherAddress,
                                                       emoji: "❤️",
                                                       sentAtTimestamp: Date.ows_millisecondTimestamp(),
                                                       receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                       transaction: transaction)
                let timestampMessage4 = startingDateMS - (3 * kHourInMs + 20 * kMinuteInMs)
                let message4 = self.buildIncomingMessage(thread: thread,
                                                         authorAddress: otherAddress,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_DIRECT_FIVE_MESSAGE_TWO",
                                                                                        comment: "This is a message. Please include the emoji."),
                                                         timestamp: timestampMessage4,
                                                         expiresInSeconds: 10800,
                                                         transaction: transaction)
                message4.debugonly_markAsReadNow(transaction: transaction)
                let attachmentMessage5 = buildAttachment(bundleFilename: "test-jpg-2.JPG",
                                                  mimeType: OWSMimeTypeImageJpeg,
                                                  transaction: transaction)
                let timestampMessage5 = startingDateMS - (2 * kHourInMs + 20 * kMinuteInMs)
                let message5 = self.buildIncomingMessage(thread: thread,
                                                         authorAddress: otherAddress,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_DIRECT_FIVE_MESSAGE_THREE",
                                                                                        comment: "This is a message."),
                                                         timestamp: timestampMessage5,
                                                         attachments: [attachmentMessage5],
                                                         expiresInSeconds: 10800,
                                                         transaction: transaction)
                message5.debugonly_markAsReadNow(transaction: transaction)
                _ = message5.recordReaction(for: localAddress,
                                                     emoji: "👍",
                                                     sentAtTimestamp: Date.ows_millisecondTimestamp(),
                                                     receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                     transaction: transaction)
                let timestampMessage6 = startingDateMS - ( 2 * kHourInMs + 2 * kMinuteInMs)
                let message6 = self.buildOutgoingMessage(thread: thread,
                                                         messageBody: nil,
                                                         timestamp: timestampMessage6,
                                                         expiresInSeconds: 10800, transaction: transaction)
                // Q: Which pack? A: Bandit the Cat.
                let packIdHex = "9acc9e8aba563d26a4994e69263e3b25"
                let packKeyHex = "5a6dff3948c28efb9b7aaf93ecc375c69fc316e78077ed26867a14d10a0f6a12"
                // Which sticker - the index in the pack.
                let stickerId0: UInt32 = 14
                if let messageSticker = self.buildMessageSticker(packIdHex: packIdHex,
                                                                 packKeyHex: packKeyHex,
                                                                 stickerId: stickerId0,
                                                                 transaction: transaction) {
                    message6.update(with: messageSticker, transaction: transaction)
                }
            }

            // Group thread received text
            if true {
                let memberAddresses = [
                    address1,
                    address2,
                    address7,
                    address6
                ]
                // avatarData should be PNG data.
                let thread = try! GroupManager.createGroupForTests(members: memberAddresses,
                                                                   name: NSLocalizedString("SCREENSHOT_NAME_GROUP_FIVE",
                                                                                           comment: "This is a group chat of family members. Please keep Kirk or replace with a common last name in your locale. Translate 'Family'"),
                                                                   avatarData: buildAvatarData(bundleFilename: "address-group-family.jpg"),
                                                                   // avatarData: nil,
                                                                   transaction: transaction)
                buildOutgoingMessage(
                    thread: thread,
                    messageBody: NSLocalizedString(
                        "SCREENSHOT_THREAD_GROUP_FIVE_MESSAGE_ONE",
                        comment: "This is a message in the group chat of family members."),
                    transaction: transaction)

                buildIncomingMessage(
                    thread: thread,
                    authorAddress: address6,
                    messageBody: NSLocalizedString(
                        "SCREENSHOT_THREAD_GROUP_FIVE_MESSAGE_TWO",
                        comment: "This is a message in the group chat of family members."),
                    timestamp: startingDateMS - (1 * kHourInMs + 58 * kMinuteInMs),
                    transaction: transaction)
            }

            // 1:1 sent media
            if true {
                let otherAddress = address5
                let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
                let timestampMessage2 = startingDateMS - (33 * kMinuteInMs)
                let message1 = self.buildOutgoingMessage(thread: thread, messageBody: NSLocalizedString("SCREENSHOT_THREAD_DIRECT_SIX_MESSAGE_ONE",
                                                                                                        comment: "This is a message."),
                                                         timestamp: timestampMessage2, transaction: transaction)
                // This marks the outgoing message as read
                // as opposed to displaying one sent check mark
                message1.update(withReadRecipient: otherAddress, recipientDeviceId: 0, readTimestamp: Date.ows_millisecondTimestamp(), transaction: transaction)
                let attachmentMessage2 = buildAttachment(bundleFilename: "test-jpg-3.JPG",
                                                         mimeType: OWSMimeTypeImageJpeg,
                                                         transaction: transaction)
                buildOutgoingMessage(
                    thread: thread,
                    messageBody: nil,
                    timestamp: timestampMessage2,
                    attachments: [attachmentMessage2], transaction: transaction)
            }

            // Group other file types -- in focus
            // Shows how to send and receive attached images.
            if true {
                // Shows how to send and receive attached images.
                // This file lives on disk in Signal/test/Assets.
                // In the project it is in Signal/Signal/test/Assets.
                // You'll need to temporarily add it to the Signal target
                // before you can use it here.
                // You can find files in the repo using something like this...
                // find . | grep -i "test-jpg"
                // ...where test-jpg is a partial file name.
                buildAttachment(bundleFilename: "test-jpg-2.JPG",
                                mimeType: OWSMimeTypeImageJpeg,
                                transaction: transaction)
                buildAttachment(bundleFilename: "test-jpg-2.JPG",
                                mimeType: OWSMimeTypeImageJpeg,
                                transaction: transaction)

                let memberAddresses = [
                    address1,
                    address4,
                    address5,
                    address6,
                    address8,
                    address9,
                    localAddress
                ]

                // avatarData should be PNG data.
                let thread = try! GroupManager.createGroupForTests(members: memberAddresses,
                                                                   name: NSLocalizedString("SCREENSHOT_NAME_GROUP_SIX",
                                                                                           comment: "This is group chat name for members talking about cats. Please include the emoji."),
                                                                   avatarData: buildAvatarData(bundleFilename: "address-group-cat.jpg"),
                                                                   transaction: transaction)
                let attachmentMessage1 = buildAttachment(bundleFilename: "nature-2-trees.JPG",
                                                         mimeType: OWSMimeTypeImageJpeg,
                                                         transaction: transaction)
                let timestampMessage1 = startingDateMS - (23 * kHourInMs + 9 * kMinuteInMs)
                let message1 = self.buildIncomingMessage(thread: thread,
                                                         authorAddress: address8,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_GROUP_SIX_MESSAGE_ONE",
                                                                                        comment: "This is a message after seeing a picture."),
                                                         timestamp: timestampMessage1,
                                                         attachments: [attachmentMessage1], transaction: transaction)
                message1.debugonly_markAsReadNow(transaction: transaction)
                let attachmentMessage2 = buildAttachment(bundleFilename: "test-jpg-3.JPG",
                                                         mimeType: OWSMimeTypeImageJpeg,
                                                         transaction: transaction)
                let timestampMessage2 = startingDateMS - (16 * kHourInMs + 5 * kMinuteInMs)
                let message2 = self.buildIncomingMessage(thread: thread,
                                                         authorAddress: address5,
                                                         messageBody: nil,
                                                         timestamp: timestampMessage2,
                                                         attachments: [attachmentMessage2], transaction: transaction)
                message2.debugonly_markAsReadNow(transaction: transaction)
                let timestampMessage3 = startingDateMS - (4 * kHourInMs + 7 * kMinuteInMs)
                let message3 = self.buildIncomingMessage(thread: thread,
                                                         authorAddress: address9,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_GROUP_SIX_MESSAGE_TWO", comment: "This is a message."),
                                                         timestamp: timestampMessage3,
                                                         transaction: transaction)
                message3.debugonly_markAsReadNow(transaction: transaction)
                let attachmentMessage4 = buildAttachment(bundleFilename: "nature-1-sunrise.JPG",
                                                         mimeType: OWSMimeTypeImageJpeg,
                                                         transaction: transaction)
                let timestampMessage4 = startingDateMS - (4 * kHourInMs + 7 * kMinuteInMs)
                let message4 = self.buildIncomingMessage(thread: thread,
                                                         authorAddress: address9,
                                                         messageBody: nil,
                                                         timestamp: timestampMessage4,
                                                         attachments: [attachmentMessage4], transaction: transaction)
                message4.debugonly_markAsReadNow(transaction: transaction)
                let timestampMessage5 = startingDateMS - (15 * kMinuteInMs)
                let message5 = self.buildOutgoingMessage(thread: thread,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_GROUP_SIX_MESSAGE_THREE",
                                                                                        comment: "This is a message in the cat chat group."),
                                                         timestamp: timestampMessage5,
                                                         transaction: transaction)
                _ = message5.recordReaction(for: address1,
                                                     emoji: "😂",
                                                     sentAtTimestamp: Date.ows_millisecondTimestamp(),
                                                     receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                     transaction: transaction)
                _ = message5.recordReaction(for: address4,
                                                     emoji: "😮",
                                                     sentAtTimestamp: Date.ows_millisecondTimestamp(),
                                                     receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                     transaction: transaction)
                _ = message5.recordReaction(for: address5,
                                                     emoji: "😮",
                                                     sentAtTimestamp: Date.ows_millisecondTimestamp(),
                                                     receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                     transaction: transaction)
                let timestampMessage6 = startingDateMS - (13 * kMinuteInMs)
                let message6 = self.buildIncomingMessage(thread: thread,
                                                         authorAddress: address6,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_GROUP_SIX_MESSAGE_FOUR", comment: "This is a message in the cat chat group."),
                                                         timestamp: timestampMessage6,
                                                         transaction: transaction)
                message6.debugonly_markAsReadNow(transaction: transaction)
                let attachmentMessage7 = buildAttachment(bundleFilename: "test-jpg-3.JPG",
                                                         mimeType: OWSMimeTypeImageJpeg,
                                                         transaction: transaction)
                buildOutgoingMessage(thread: thread,
                                     messageBody: nil,
                                     timestamp: startingDateMS - (9 * kMinuteInMs),
                                     attachments: [attachmentMessage7],
                                     isViewOnceMessage: true,
                                     transaction: transaction)
                let attachmentMessage8 = buildAttachment(bundleFilename: "certificate.PDF",
                                                         mimeType: "application/pdf",
                                                         sourceFilename: NSLocalizedString("SCREENSHOT_THREAD_GROUP_SIX_FILE_NAME", comment: "This is a file name 'Instructions' for the cat chat group."),
                                                         transaction: transaction)
                let timestampMessage8 = startingDateMS - (9 * kMinuteInMs)
                let message8 = self.buildIncomingMessage(thread: thread,
                                                         authorAddress: address4,
                                                         messageBody: NSLocalizedString("SCREENSHOT_THREAD_GROUP_SIX_MESSAGE_FIVE", comment: "This is a message in the cat chat group."),
                                                         timestamp: timestampMessage8,
                                                         attachments: [attachmentMessage8], transaction: transaction)
                message8.debugonly_markAsReadNow(transaction: transaction)
            }

            // Third thread 1:1 received voice message
            if true {
                let otherAddress = address2
                let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
                // This will be a build warning because you're not using the message1 variable.
                // you can fix that by saying:
                // _ = self.buildOutgoingMessage(...)
                let timestampMessage7 = startingDateMS - (4 * kMinuteInMs)
                buildIncomingMessage(thread: thread, authorAddress: otherAddress, messageBody: "1", timestamp: timestampMessage7, transaction: transaction)
                buildIncomingMessage(thread: thread, authorAddress: otherAddress, messageBody: "2", timestamp: timestampMessage7, transaction: transaction)
                buildIncomingMessage(thread: thread, authorAddress: otherAddress, messageBody: "3", timestamp: timestampMessage7, transaction: transaction)
                buildIncomingMessage(thread: thread, authorAddress: otherAddress, messageBody: "4.", timestamp: timestampMessage7, transaction: transaction)
                buildIncomingMessage(thread: thread, authorAddress: otherAddress, messageBody: "5", timestamp: timestampMessage7, transaction: transaction)
                buildIncomingMessage(thread: thread, authorAddress: otherAddress, messageBody: "6", timestamp: timestampMessage7, transaction: transaction)
                let attachmentMessage7 = buildAttachment(bundleFilename: "sonarping.mp3",
                                                         mimeType: "audio/mp3",
                                                         transaction: transaction)
                attachmentMessage7.attachmentType = .voiceMessage
                attachmentMessage7.anyOverwritingUpdate(transaction: transaction)
                buildIncomingMessage(thread: thread, authorAddress: otherAddress, messageBody: nil, timestamp: timestampMessage7, attachments: [attachmentMessage7], transaction: transaction)
            }

            // Second Thread -- Missed call or emoji on iPad
            if true {
                let otherAddress = address1
                let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
                buildIncomingMessage(
                    thread: thread,
                    authorAddress: otherAddress,
                    messageBody: "🤣🤣🤣",
                    timestamp: startingDateMS - (3 * kMinuteInMs),
                    transaction: transaction)

                buildIncomingMessage(
                    thread: thread,
                    authorAddress: otherAddress,
                    messageBody: NSLocalizedString(
                        "SCREENSHOT_THREAD_DIRECT_SEVEN_MESSAGE_ONE",
                        comment: "This is a message before a call."),
                    timestamp: startingDateMS - (2 * kMinuteInMs),
                    transaction: transaction)

                // Replace .incomingIncomplete with other values to create other record types.
                // Note that you have to remove the obj-c enum prefix.
                //
                //                typedef NS_ENUM(NSUInteger, RPRecentCallType) {
                //                    RPRecentCallTypeIncoming = 1,
                //                    RPRecentCallTypeOutgoing,
                //                    RPRecentCallTypeIncomingMissed,
                //                    // These call types are used until the call connects.
                //                    RPRecentCallTypeOutgoingIncomplete,
                //                    RPRecentCallTypeIncomingIncomplete,
                //                    RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity,
                //                    RPRecentCallTypeIncomingDeclined,
                //                    RPRecentCallTypeOutgoingMissed,
                //                };
                let callRecord = TSCall(callType: .incomingMissed,
                                        offerType: .audio,
                                        thread: thread,
                                        sentAtTimestamp: Date.ows_millisecondTimestamp())
                callRecord.anyInsert(transaction: transaction)
            }

            // First message for disappearing message time set
            // Adjust the time of alert or keep this first
            if true {
                let otherAddress = address8
                let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
//                let message1 = self.buildOutgoingMessage(thread: thread, messageBody: "Hi yup.", transaction: transaction)
//                // This marks the outgoing message as read
//                // as opposed to displaying one sent check mark
//                message1.update(withReadRecipient: otherAddress, readTimestamp: Date.ows_millisecondTimestamp(), transaction: transaction)
//                let timestampMessage2 = startingDateMS - (30 * kHourInMs + 42 * kMinuteInMs)
//                let message2 = self.buildIncomingMessage(thread: thread,
//                                                         authorAddress: otherAddress,
//                                                         messageBody: "Thanks! What a wonderful message to read :)", transaction: transaction)
//                // This marks the incoming message as read
//                // so the "New Messages" indicator/ "Today" is not displayed
//                message2.debugonly_markAsReadNow(transaction: transaction)
                GroupManager.remoteUpdateDisappearingMessages(withContactOrV1GroupThread: thread,
                                                              disappearingMessageToken: DisappearingMessageToken(isEnabled: true, durationSeconds: UInt32(24 * kHourInterval)),
                                                              groupUpdateSourceAddress: localAddress,
                                                              transaction: transaction)
            }

//            // Example of how to enable or disable disappearing messages.
//            if true {
//                let memberAddresses = [
//                    address1,
//                    address2,
//                ]
//                // avatarData should be PNG data.
//                let thread = try! GroupManager.createGroupForTests(members: memberAddresses,
//                                                                   name: "DMs",
//                                                                   avatarData: nil,
//                                                                   transaction: transaction)
//                let message1 = self.buildOutgoingMessage(thread: thread, messageBody: "", transaction: transaction)
//                // Enable DMs.
//                //
//                // For the purposes of this debug UI, it's simplest to use the
//                // "remote" flavor of this message which is sync.
//                GroupManager.remoteUpdateDisappearingMessages(withContactOrV1GroupThread: thread,
//                                                              disappearingMessageToken: DisappearingMessageToken(isEnabled: true, durationSeconds: UInt32(24 * kHourInterval)),
//                                                              groupUpdateSourceAddress: localAddress,
//                                                              transaction: transaction)
//                // Disable DMs.
//                GroupManager.remoteUpdateDisappearingMessages(withContactOrV1GroupThread: thread,
//                                                              disappearingMessageToken: DisappearingMessageToken.disabledToken,
//                                                              groupUpdateSourceAddress: localAddress,
//                                                              transaction: transaction)
//            }

//            // Example of how insert call messages.
//            if true {
//                let otherAddress = address1
//                let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
//                
//                // I think this is a "missed incoming" call.
//                //
//                // Replace .incomingIncomplete with other values to create other record types.
//                // Note that you have to remove the obj-c enum prefix.
//                //
//                //                typedef NS_ENUM(NSUInteger, RPRecentCallType) {
//                //                    RPRecentCallTypeIncoming = 1,
//                //                    RPRecentCallTypeOutgoing,
//                //                    RPRecentCallTypeIncomingMissed,
//                //                    // These call types are used until the call connects.
//                //                    RPRecentCallTypeOutgoingIncomplete,
//                //                    RPRecentCallTypeIncomingIncomplete,
//                //                    RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity,
//                //                    RPRecentCallTypeIncomingDeclined,
//                //                    RPRecentCallTypeOutgoingMissed,
//                //                };
////                let callRecord = TSCall(callType: .incomingIncomplete,
////                                        in: thread,
////                                        sentAtTimestamp: Date.ows_millisecondTimestamp())
//                let callRecord = TSCall(callType: .incomingMissed,
//                in: thread,
//                sentAtTimestamp: Date.ows_millisecondTimestamp())
//                callRecord.anyInsert(transaction: transaction)
//            }

//            // Example of how to insert reactions.
//            if true {
//                let memberAddresses = [
//                    address1,
//                    address2,
//                ]
//                // avatarData should be PNG data.
//                let thread = try! GroupManager.createGroupForTests(members: memberAddresses,
//                                                                   name: "Reactions",
//                                                                   avatarData: nil,
//                                                                   transaction: transaction)
//                let outgoingMessage = self.buildOutgoingMessage(thread: thread, messageBody: "something", transaction: transaction)
//                let incomingMessage = self.buildIncomingMessage(thread: thread,
//                                                                authorAddress: address1,
//                                                                messageBody: "Welcome... 1", transaction: transaction)
//
//                // Local user (for this device) likes a given message.
//                //
//                // Reference: ["❤️", "👍", "👎", "😂", "😮", "😢", "😡"]
//                let _ = incomingMessage.recordReaction(for: localAddress,
//                                                       emoji: "❤️",
//                                                       sentAtTimestamp: Date.ows_millisecondTimestamp(),
//                                                       receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
//                                                       transaction: transaction)
//
//                // Some other user reacts to a given message.
//                let _ = outgoingMessage.recordReaction(for: address1,
//                                                       emoji: "👍",
//                                                       sentAtTimestamp: Date.ows_millisecondTimestamp(),
//                                                       receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
//                                                       transaction: transaction)
//            }

//            // Example of how to insert stickers.
//            if true {
//                let memberAddresses = [
//                    address1,
//                    address2,
//                ]
//                // avatarData should be PNG data.
//                let thread = try! GroupManager.createGroupForTests(members: memberAddresses,
//                                                                   name: "Stickers",
//                                                                   avatarData: nil,
//                                                                   transaction: transaction)
//                let outgoingMessage = self.buildOutgoingMessage(thread: thread, messageBody: "", transaction: transaction)
//                let incomingMessage = self.buildIncomingMessage(thread: thread,
//                                                                authorAddress: address1,
//                                                                messageBody: "Welcome... 1", transaction: transaction)
//
//                // Q: Which pack? A: Bandit the Cat.
//                let packIdHex = "9acc9e8aba563d26a4994e69263e3b25"
//                let packKeyHex = "5a6dff3948c28efb9b7aaf93ecc375c69fc316e78077ed26867a14d10a0f6a12"
//                // Which sticker - the index in the pack.
//                let stickerId0: UInt32 = 0
//                let stickerId1: UInt32 = 1
//
//                if let messageSticker = self.buildMessageSticker(packIdHex: packIdHex,
//                                                                 packKeyHex: packKeyHex,
//                                                                 stickerId: stickerId0,
//                                                                 transaction: transaction) {
//                    incomingMessage.update(with: messageSticker, transaction: transaction)
//                }
//                if let messageSticker = self.buildMessageSticker(packIdHex: packIdHex,
//                                                                 packKeyHex: packKeyHex,
//                                                                 stickerId: stickerId1,
//                                                                 transaction: transaction) {
//                    outgoingMessage.update(with: messageSticker, transaction: transaction)
//                }
//            }
        }
    }

    private class func buildMessageSticker(packIdHex: String, packKeyHex: String, stickerId: UInt32, transaction: SDSAnyWriteTransaction) -> MessageSticker? {
        guard let stickerPackInfo = StickerPackInfo.parsePackIdHex(packIdHex, packKeyHex: packKeyHex) else {
            owsFailDebug("Invalid info")
            return nil
        }
        let allPacks: [StickerPack] = StickerManager.installedStickerPacks(transaction: transaction)
        // Find the pack with the matching pack id.
        let packList = allPacks.filter { $0.info.packId == stickerPackInfo.packId }
        guard let pack: StickerPack = packList.first else {
            owsFailDebug("Sticker pack not installed?")
            return nil
        }
        // Find the sticker with the matching stickerId.
        let stickerInfos: [StickerInfo] = pack.stickerInfos.filter { $0.stickerId == stickerId }
        guard let stickerInfo = stickerInfos.first else {
            owsFailDebug("Couldn't find sticker info in pack.")
            return nil
        }
        guard let stickerMetadata = StickerManager.installedStickerMetadataWithSneakyTransaction(stickerInfo: stickerInfo) else {
            owsFailDebug("Couldn't find sticker metadata.")
            return nil
        }
        do {
            let stickerData = try Data(contentsOf: stickerMetadata.stickerDataUrl)
            let stickerDraft = MessageStickerDraft(info: stickerInfo,
                                                   stickerData: stickerData,
                                                   stickerType: stickerMetadata.stickerType,
                                                   emoji: stickerMetadata.firstEmoji)
            let messageSticker = try MessageSticker.buildValidatedMessageSticker(fromDraft: stickerDraft,
                                                                                 transaction: transaction)
            return messageSticker
        } catch {
            owsFailDebug("Couldn't create sticker: \(error).")
            return nil
        }
    }

//    private class func ensureAccount(phoneNumber: String,
//                                     uuidString: String,
//                                     givenName: String,
//                                     familyName: String?,
//                                     transaction: SDSAnyWriteTransaction) -> SignalServiceAddress {
//        let uuid = UUID(uuidString: uuidString)!
//        let address = SignalServiceAddress(uuid: uuid, phoneNumber: phoneNumber)
//        self.profileManager.setProfileGivenName(givenName,
//                                                familyName: familyName,
//                                                for: address,
//                                                userProfileWriter: .debugging,
//                                                transaction: transaction)
//
//        let contact = self.buildContact(address: address, fullName: givenName, transaction: transaction)
//        if let existingAccount = contactsManager.fetchSignalAccount(for: address, transaction: transaction) {
//            // Do nothing.
//            existingAccount.contact = contact
//            existingAccount.anyOverwritingUpdate(transaction: transaction)
//        } else {
//            let newAccount = SignalAccount(contact: contact,
//                                           contactAvatarHash: nil,
//                                           contactAvatarJpegData: nil,
//                                           multipleAccountLabelText: "",
//                                           recipientPhoneNumber: phoneNumber,
//                                           recipientUUID: uuidString)
//            newAccount.anyInsert(transaction: transaction)
//        }
//        return address
//    }

    private class func ensureAccount(phoneNumber: String,
                                     uuidString: String,
                                     givenName: String,
                                     familyName: String?,
                                     avatarBundleFilename: String? = nil,
                                     transaction: SDSAnyWriteTransaction) -> SignalServiceAddress {
        let uuid = UUID(uuidString: uuidString)!
        let address = SignalServiceAddress(uuid: uuid, phoneNumber: phoneNumber)
        self.profileManager.setProfileGivenName(givenName,
                                                familyName: familyName,
                                                for: address,
                                                userProfileWriter: .debugging,
                                                transaction: transaction)

        if let avatarBundleFilename = avatarBundleFilename {
            let resourceUrl = Bundle.main.resourceURL!
            let fileUrl = resourceUrl.appendingPathComponent(avatarBundleFilename)
            let avatarData = try! Data(contentsOf: fileUrl)
            let avatarFileName = UUID().uuidString + ".jpg"
            try! avatarData.write(to: URL(fileURLWithPath: OWSUserProfile.profileAvatarFilepath(withFilename: avatarFileName)), options: .atomic)
            let profile = OWSUserProfile.getOrBuild(for: address, transaction: transaction)
            profile.update(avatarFileName: avatarFileName,
                           userProfileWriter: .debugging,
                           transaction: transaction)
        }
        let contact = self.buildContact(address: address, fullName: givenName, transaction: transaction)
        if let existingAccount = contactsManagerImpl.fetchSignalAccount(for: address, transaction: transaction) {
            existingAccount.updateWithContact(contact, transaction: transaction)
        } else {
            let newAccount = SignalAccount(contact: contact,
                                           contactAvatarHash: nil,
                                           multipleAccountLabelText: "",
                                           recipientPhoneNumber: phoneNumber,
                                           recipientUUID: uuidString)
            newAccount.anyInsert(transaction: transaction)
        }
        return address
    }

    private class func setLocalProfile(givenName: String,
                                       familyName: String?,
                                       avatarBundleFilename: String? = nil) {
        let avatarData: Data?
        if let avatarBundleFilename = avatarBundleFilename {
            let resourceUrl = Bundle.main.resourceURL!
            let fileUrl = resourceUrl.appendingPathComponent(avatarBundleFilename)
            avatarData = try! Data(contentsOf: fileUrl)
        } else {
            avatarData = nil
        }

        firstly(on: .global()) {
            OWSProfileManager.updateLocalProfilePromise(
                profileGivenName: givenName,
                profileFamilyName: familyName,
                profileBio: nil,
                profileBioEmoji: nil,
                profileAvatarData: avatarData,
                visibleBadgeIds: [],
                userProfileWriter: .debugging
            ).asVoid()
        }.catch(on: .global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private class func buildContact(address: SignalServiceAddress, fullName: String, transaction: SDSAnyWriteTransaction) -> Contact {
        var userTextPhoneNumbers: [String] = []
        var phoneNumberNameMap: [String: String] = [:]
        var parsedPhoneNumbers: [PhoneNumber] = []
        if let phoneNumber = address.phoneNumber,
            let parsedPhoneNumber = PhoneNumber(fromE164: phoneNumber) {
            userTextPhoneNumbers.append(phoneNumber)
            parsedPhoneNumbers.append(parsedPhoneNumber)
            phoneNumberNameMap[parsedPhoneNumber.toE164()] = CommonStrings.mainPhoneNumberLabel
        }

        guard let serviceIdentifier = address.serviceIdentifier else {
            owsFail("serviceIdentifier was unexpectedly nil")
        }

        return Contact(uniqueId: serviceIdentifier,
                       cnContactId: nil,
                       firstName: nil,
                       lastName: nil,
                       nickname: nil,
                       fullName: fullName,
                       userTextPhoneNumbers: userTextPhoneNumbers,
                       phoneNumberNameMap: phoneNumberNameMap,
                       parsedPhoneNumbers: parsedPhoneNumbers,
                       emails: [])
    }

    @discardableResult
    private class func buildOutgoingMessage(thread: TSThread,
                                            messageBody: String?,
                                            timestamp: UInt64? = nil,
                                            attachments: [TSAttachmentStream]? = nil,
                                            expiresInSeconds: UInt32? = nil,
                                            isViewOnceMessage: Bool? = false,
                                            transaction: SDSAnyWriteTransaction) -> TSOutgoingMessage {
        // Manipulate when the message was sent here.
        //
        // e.g. "yesterday" would be: Date.ows_millisecondTimestamp() - kDayInMs
        let builder = TSOutgoingMessageBuilder(thread: thread, messageBody: messageBody)
        if let timestamp = timestamp {
            builder.timestamp = timestamp
        }
        if let attachments = attachments {
            for attachment in attachments {
                builder.addAttachmentId(attachment.uniqueId)
            }
        }
        if let expiresInSeconds = expiresInSeconds {
            builder.expiresInSeconds = expiresInSeconds
        }
        if let isViewOnceMessage = isViewOnceMessage {
                   builder.isViewOnceMessage = isViewOnceMessage
        }
        let message = builder.build()
        message.replaceReceivedAtTimestamp(timestamp ?? Date.ows_millisecondTimestamp())
        message.anyInsert(transaction: transaction)
        // Mark as sent.
        message.update(withFakeMessageState: .sent, transaction: transaction)

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address.")
            return message
        }
        // Find some recipient of the message (who isn't us).
        guard let otherAddress = (thread.recipientAddresses.filter { $0 != localAddress }.first) else {
            owsFailDebug("Couldn't find other address in thread.")
            return message
        }
        // Mark as sent to someone.
        message.update(withSentRecipient: otherAddress, wasSentByUD: false, transaction: transaction)
        // Mark as delivered by someone.
        message.update(withDeliveredRecipient: otherAddress,
                       recipientDeviceId: 0,
                       deliveryTimestamp: nil,
                       transaction: transaction)
        // Mark as read by someone.
        message.update(withReadRecipient: otherAddress,
                       recipientDeviceId: 0,
                       readTimestamp: Date.ows_millisecondTimestamp(),
                       transaction: transaction )

        return message
    }

    @discardableResult
    private class func buildIncomingMessage(thread: TSThread,
                                            authorAddress: SignalServiceAddress,
                                            messageBody: String?,
                                            timestamp: UInt64? = nil,
                                            attachments: [TSAttachmentStream]? = nil,
                                            expiresInSeconds: UInt32? = nil,
                                            isViewOnceMessage: Bool? = false,
                                            transaction: SDSAnyWriteTransaction) -> TSIncomingMessage {
        // Manipulate when the message was sent here.
        //
        // e.g. "yesterday" would be: Date.ows_millisecondTimestamp() - kDayInMs
        let timestamp = timestamp ?? Date.ows_millisecondTimestamp()
        var attachmentIds = [String]()
        if let attachments = attachments {
            attachmentIds = attachments.map { $0.uniqueId }
        }
        let expiresInSeconds = expiresInSeconds ?? 0
        let isViewOnceMessage = isViewOnceMessage ?? false
        let message = TSIncomingMessageBuilder(thread: thread,
                                               timestamp: timestamp,
                                               authorAddress: authorAddress,
                                               messageBody: messageBody,
                                               attachmentIds: attachmentIds,
                                               expiresInSeconds: expiresInSeconds,
                                               isViewOnceMessage: isViewOnceMessage).build()
        message.replaceReceivedAtTimestamp(timestamp)
        message.anyInsert(transaction: transaction)
        return message
    }

    private class func buildAvatarData(bundleFilename: String) -> Data {
        let resourceUrl = Bundle.main.resourceURL!
        let fileUrl = resourceUrl.appendingPathComponent(bundleFilename)
        return try! Data(contentsOf: fileUrl)
    }

    @discardableResult
    private class func buildAttachment(bundleFilename: String,
                                       mimeType: String,
                                       sourceFilename: String? = nil,
                                       caption: String? = nil,
                                       transaction: SDSAnyWriteTransaction) -> TSAttachmentStream {

        // Content types are MIME types
        // See: MIMETypeUtil.h
        let resourceUrl = Bundle.main.resourceURL!
        let fileUrl = resourceUrl.appendingPathComponent(bundleFilename)
        let fileSize = OWSFileSystem.fileSize(of: fileUrl)!.intValue
        let attachment = TSAttachmentStream(contentType: mimeType,
                                            byteCount: UInt32(fileSize),
                                            // This doesn't matter much unless you export the file.
            // You can leave it nil.
            sourceFilename: sourceFilename,
            caption: caption,
            // If you want an album, make sure that they all have the same album id.
            albumMessageId: nil)

        let fileData = try! Data(contentsOf: fileUrl)
        try! attachment.write(fileData)
        attachment.anyInsert(transaction: transaction)
        attachment.updateAsUploaded(withEncryptionKey: Randomness.generateRandomBytes(1),
                                    digest: Randomness.generateRandomBytes(1),
                                    serverId: 1,
                                    cdnKey: "",
                                    cdnNumber: 0,
                                    uploadTimestamp: Date.ows_millisecondTimestamp(),
                                    transaction: transaction)
        return attachment
    }
}

#endif
