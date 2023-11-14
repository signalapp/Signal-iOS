//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal
import SignalMessaging

class VisibleBadgeResolverTest: XCTestCase {

    typealias Badge = ProfileBadgesSnapshot.Badge
    typealias SwitchType = VisibleBadgeResolver.SwitchType

    func testVisibleBadgeIds() {
        struct TestCase {
            // The state of the user's badges, cached when the view is first presented.
            var profileBadgeIds: [String]
            var areBadgesVisible: Bool

            // The default configuration for the switch, computed when the view is
            // first presented.
            var newBadgeId: String
            var switchType: SwitchType
            var defaultSwitchValue: Bool

            // The action to perform against the user's badges, applied when redeeming
            // a gift or dismissing the sheet.
            var selectedSwitchValue: Bool
            var areBadgesVisibleWhenUpdating: Bool?
            var newVisibleBadgeIds: [String]

            static func forFirstBadge(_ badgeId: String, selectedSwitchValue: Bool) -> Self {
                Self(
                    profileBadgeIds: [],
                    areBadgesVisible: false,
                    newBadgeId: badgeId,
                    switchType: .displayOnProfile,
                    defaultSwitchValue: true,
                    selectedSwitchValue: selectedSwitchValue,
                    newVisibleBadgeIds: selectedSwitchValue ? [badgeId] : []
                )
            }
        }
        let testCases: [TestCase] = [
            // You don't have any badges.
            // Show "Display on Profile" and default the switch to on.
            .forFirstBadge("GIFT", selectedSwitchValue: false),
            .forFirstBadge("GIFT", selectedSwitchValue: true),
            .forFirstBadge("R_LOW", selectedSwitchValue: false),
            .forFirstBadge("R_LOW", selectedSwitchValue: true),
            .forFirstBadge("BOOST", selectedSwitchValue: false),
            .forFirstBadge("BOOST", selectedSwitchValue: true),

            // You already have a Sustainer badge on your profile and are redeeming a gift.
            // Show "Make Featured Badge" and default the switch to off.
            TestCase(
                profileBadgeIds: ["R_LOW"],
                areBadgesVisible: true,
                newBadgeId: "GIFT",
                switchType: .makeFeaturedBadge,
                defaultSwitchValue: false,
                selectedSwitchValue: false,
                newVisibleBadgeIds: ["R_LOW", "GIFT"]
            ),

            // You already have a Boost badge on your profile and are redeeming a gift.
            // Show "Make Featured Badge" and default the switch to on.
            TestCase(
                profileBadgeIds: ["BOOST"],
                areBadgesVisible: true,
                newBadgeId: "GIFT",
                switchType: .makeFeaturedBadge,
                defaultSwitchValue: true,
                selectedSwitchValue: true,
                newVisibleBadgeIds: ["GIFT", "BOOST"]
            ),

            // You already have a Gift badge on your profile and are buying a subscription.
            // Show "Make Featured Badge" and default the switch to on.
            TestCase(
                profileBadgeIds: ["GIFT"],
                areBadgesVisible: true,
                newBadgeId: "R_LOW",
                switchType: .makeFeaturedBadge,
                defaultSwitchValue: true,
                selectedSwitchValue: false,
                newVisibleBadgeIds: ["GIFT", "R_LOW"]
            ),

            // You already have a Boost badge on your profile and purchase another one.
            // Don't show any switch.
            TestCase(
                profileBadgeIds: ["BOOST"],
                areBadgesVisible: true,
                newBadgeId: "BOOST",
                switchType: .none,
                defaultSwitchValue: true,
                selectedSwitchValue: true,
                newVisibleBadgeIds: ["BOOST"]
            ),

            // You already have a Boost badge that you've hidden, and you purchase another one.
            // Show "Display on Profile".
            TestCase(
                profileBadgeIds: ["BOOST"],
                areBadgesVisible: false,
                newBadgeId: "BOOST",
                switchType: .displayOnProfile,
                defaultSwitchValue: true,
                selectedSwitchValue: false,
                newVisibleBadgeIds: []
            ),

            // You have a Boost and Sustainer badge visible on your profile, and you purchase a Boost.
            // Don't show any switch.
            TestCase(
                profileBadgeIds: ["BOOST", "R_LOW"],
                areBadgesVisible: true,
                newBadgeId: "BOOST",
                switchType: .none,
                defaultSwitchValue: true,
                selectedSwitchValue: true,
                newVisibleBadgeIds: ["BOOST", "R_LOW"]
            ),

            // EDGE CASES THAT REQUIRE BADGE UPDATES FROM IPAD / BADGE EXPIRATIONS

            // You have hidden Boost/Gift badges, you purchase a Boost, and you unhide badges on another device.
            // Selecting "off" for "Display on Profile" keeps the badge visible but no longer features it.
            TestCase(
                profileBadgeIds: ["BOOST", "GIFT"],
                areBadgesVisible: false,
                newBadgeId: "BOOST",
                switchType: .displayOnProfile,
                defaultSwitchValue: true,
                selectedSwitchValue: false,
                areBadgesVisibleWhenUpdating: true,
                newVisibleBadgeIds: ["GIFT", "BOOST"]
            ),

            // You have a hidden Gift badge, you purchase a Boost, and you unhide badges on another device.
            // Selecting "off" for "Display on Profile" will result in the new badge being shown.
            TestCase(
                profileBadgeIds: ["GIFT"],
                areBadgesVisible: false,
                newBadgeId: "BOOST",
                switchType: .displayOnProfile,
                defaultSwitchValue: true,
                selectedSwitchValue: false,
                areBadgesVisibleWhenUpdating: true,
                newVisibleBadgeIds: ["GIFT", "BOOST"]
            ),

            // You have a visible Gift badge, you purchase a Boost, and you hide badges on another device.
            // Selecting "off" for "Make Featured Badge" will result in all badges being hidden.
            TestCase(
                profileBadgeIds: ["GIFT"],
                areBadgesVisible: true,
                newBadgeId: "BOOST",
                switchType: .makeFeaturedBadge,
                defaultSwitchValue: true,
                selectedSwitchValue: false,
                areBadgesVisibleWhenUpdating: false,
                newVisibleBadgeIds: []
            ),

            // You have a visible Gift badge, you purchase a Boost, and you hide badges on another device.
            // Selecting "on" for "Make Featured Badge" will result in all badges being visible.
            TestCase(
                profileBadgeIds: ["GIFT"],
                areBadgesVisible: true,
                newBadgeId: "BOOST",
                switchType: .makeFeaturedBadge,
                defaultSwitchValue: true,
                selectedSwitchValue: true,
                areBadgesVisibleWhenUpdating: false,
                newVisibleBadgeIds: ["BOOST", "GIFT"]
            )
        ]

        for testCase in testCases {
            let initialResolver = VisibleBadgeResolver(
                badgesSnapshot: ProfileBadgesSnapshot(
                    existingBadges: testCase.profileBadgeIds.map {
                        .init(id: $0, isVisible: testCase.areBadgesVisible)
                    }
                )
            )

            let switchType = initialResolver.switchType(for: testCase.newBadgeId)
            XCTAssertEqual(switchType, testCase.switchType, "\(testCase)")

            let defaultSwitchValue = initialResolver.switchDefault(for: testCase.newBadgeId)
            XCTAssertEqual(defaultSwitchValue, testCase.defaultSwitchValue, "\(testCase)")

            // If no switch is shown, the default value must match the selected value.
            if switchType == .none {
                XCTAssertEqual(testCase.selectedSwitchValue, testCase.defaultSwitchValue, "\(testCase)")
            }

            // a short while later

            let updateResolver = VisibleBadgeResolver(
                badgesSnapshot: ProfileBadgesSnapshot(
                    existingBadges: testCase.profileBadgeIds.map {
                        .init(id: $0, isVisible: testCase.areBadgesVisibleWhenUpdating ?? testCase.areBadgesVisible)
                    }
                )
            )

            let visibleBadgeIds = updateResolver.visibleBadgeIds(
                adding: testCase.newBadgeId,
                isVisibleAndFeatured: testCase.selectedSwitchValue
            )
            XCTAssertEqual(visibleBadgeIds, testCase.newVisibleBadgeIds, "\(testCase)")
        }

    }

    func testCurrentlyVisibleBadgeIds() {
        let badgeA = Badge(id: "A", isVisible: true)
        let badgeB = Badge(id: "B", isVisible: true)
        let badgeC = Badge(id: "C", isVisible: false)
        let badgeD = Badge(id: "D", isVisible: false)

        let testCases: [([Badge], [String])] = [
            ([], []),
            ([badgeA], ["A"]),
            ([badgeA, badgeB], ["A", "B"]),
            ([badgeC], []),
            ([badgeC, badgeD], []),
            ([badgeA, badgeC], ["A"]),
            ([badgeC, badgeA], ["A"]),
            ([badgeA, badgeB, badgeC], ["A", "B"]),
            ([badgeA, badgeC, badgeB], ["A", "B"]),
            ([badgeC, badgeA, badgeD], ["A"])
        ]

        for (existingBadges, visibleBadgeIds) in testCases {
            let visibleBadgeResolver = VisibleBadgeResolver(
                badgesSnapshot: ProfileBadgesSnapshot(existingBadges: existingBadges)
            )
            XCTAssertEqual(visibleBadgeResolver.currentlyVisibleBadgeIds(), visibleBadgeIds)
        }
    }

}
