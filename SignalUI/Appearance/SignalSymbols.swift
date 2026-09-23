//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import NaturalLanguage
import SignalServiceKit
public import SwiftUI

public enum SignalSymbol: Character {

    // MARK: - Symbols

    //
    // Generated from `signal-symbols/font/symbols.json` in the Signal-Design
    // repo (Signal Symbols 4.0), camel cased. A trailing comment marks the few
    // cases whose name deliberately differs from the manifest.

    case album = "\u{E163}"
    case albumFill = "\u{E20D}"
    case albumFillWide = "\u{E20E}"
    case albumPlus = "\u{E294}"
    case albumPlusFill = "\u{E21F}"
    case albumPlusFillWide = "\u{E220}"
    case albumPlusWide = "\u{E295}"
    case albumWide = "\u{E001}"
    case appearance = "\u{E031}"
    case appearanceFill = "\u{E164}"
    case archive = "\u{E09B}"
    case archiveAltDown = "\u{E09D}"
    case archiveAltDownFill = "\u{E167}"
    case archiveAltUp = "\u{E09E}"
    case archiveAltUpFill = "\u{E168}"
    case archiveDown = "\u{E205}"
    case archiveDownFill = "\u{E206}"
    case archiveFill = "\u{E165}"
    case archiveUp = "\u{E09C}"
    case archiveUpFill = "\u{E166}"
    case arrowCircleDashedDown = "\u{E172}"
    case arrowCircleDashedDownLeft = "\u{E29D}"
    case arrowCircleDashedDownRight = "\u{E29E}"
    case arrowCircleDashedLeft = "\u{E237}"
    case arrowCircleDashedRight = "\u{E238}"
    case arrowCircleDashedUp = "\u{E239}"
    case arrowCircleDashedUpLeft = "\u{E29B}"
    case arrowCircleDashedUpRight = "\u{E29C}"
    case arrowCircleDown = "\u{E00E}"
    case arrowCircleDownFill = "\u{E006}"
    case arrowCircleDownLeft = "\u{E011}"
    case arrowCircleDownLeftFill = "\u{E009}"
    case arrowCircleDownRight = "\u{E012}"
    case arrowCircleDownRightFill = "\u{E00A}"
    case arrowCircleLeft = "\u{E00B}"
    case arrowCircleLeftFill = "\u{E003}"
    case arrowCircleRight = "\u{E00C}"
    case arrowCircleRightFill = "\u{E004}"
    case arrowCircleUp = "\u{E00D}"
    case arrowCircleUpFill = "\u{E005}"
    case arrowCircleUpLeft = "\u{E00F}"
    case arrowCircleUpLeftFill = "\u{E007}"
    case arrowCircleUpRight = "\u{E010}"
    case arrowCircleUpRightFill = "\u{E008}"
    case arrowCounterclockwise = "\u{E296}"
    case arrowDown = "\u{E16C}"
    case arrowDownLeft = "\u{E16F}"
    case arrowDownRight = "\u{E170}"
    case arrowInwardUpLeftDownRight = "\u{E11E}"
    case arrowInwardUpLeftUpRightDownLeftDownRight = "\u{E11C}"
    case arrowInwardUpRightDownLeft = "\u{E11D}"
    case arrowLeft = "\u{E169}"
    case arrowLeftRight = "\u{E0CF}"
    case arrowOutwardUpLeftDownRight = "\u{E119}"
    case arrowOutwardUpLeftUpRightDownLeftDownRight = "\u{E117}"
    case arrowOutwardUpRightDownLeft = "\u{E118}"
    case arrowRectangleDown = "\u{E229}"
    case arrowRectangleDownFill = "\u{E233}"
    case arrowRectangleDownFillWide = "\u{E236}"
    case arrowRectangleDownWide = "\u{E230}"
    case arrowRectangleLeft = "\u{E227}"
    case arrowRectangleLeftFill = "\u{E231}"
    case arrowRectangleLeftFillWide = "\u{E234}"
    case arrowRectangleLeftWide = "\u{E22A}"
    case arrowRectangleRight = "\u{E228}"
    case arrowRectangleRightFill = "\u{E232}"
    case arrowRectangleRightFillWide = "\u{E235}"
    case arrowRectangleRightWide = "\u{E22B}"
    case arrowRectangleUp = "\u{E0CD}"
    case arrowRectangleUpFill = "\u{E173}"
    case arrowRectangleUpWide = "\u{E171}"
    case arrowRight = "\u{E16A}"
    case arrowSquareDown = "\u{E016}"
    case arrowSquareDownFill = "\u{E08D}"
    case arrowSquareDownLeft = "\u{E019}"
    case arrowSquareDownLeftFill = "\u{E090}"
    case arrowSquareDownRight = "\u{E01A}"
    case arrowSquareDownRightFill = "\u{E091}"
    case arrowSquareInwardUpLeftDownRight = "\u{E21D}"
    case arrowSquareInwardUpLeftDownRightFill = "\u{E21E}"
    case arrowSquareInwardUpRightDownLeft = "\u{E21B}"
    case arrowSquareInwardUpRightDownLeftFill = "\u{E21C}"
    case arrowSquareLeft = "\u{E013}"
    case arrowSquareLeftFill = "\u{E08A}"
    case arrowSquareLeftRight = "\u{E297}"
    case arrowSquareLeftRightFill = "\u{E299}"
    case arrowSquareOutwardUpLeftDownRight = "\u{E22E}"
    case arrowSquareOutwardUpLeftDownRightFill = "\u{E22F}"
    case arrowSquareOutwardUpRightDownLeft = "\u{E22C}"
    case arrowSquareOutwardUpRightDownLeftFill = "\u{E22D}"
    case arrowSquareRight = "\u{E014}"
    case arrowSquareRightFill = "\u{E08B}"
    case arrowSquareUp = "\u{E015}"
    case arrowSquareUpDown = "\u{E298}"
    case arrowSquareUpDownFill = "\u{E29A}"
    case arrowSquareUpFill = "\u{E08C}"
    case arrowSquareUpLeft = "\u{E017}"
    case arrowSquareUpLeftFill = "\u{E08E}"
    case arrowSquareUpRight = "\u{E018}"
    case arrowSquareUpRightFill = "\u{E08F}"
    case arrowUp = "\u{E16B}"
    case arrowUpDown = "\u{E0CE}"
    case arrowUpLeft = "\u{E16D}"
    case arrowUpRight = "\u{E16E}"
    case aspectRatio = "\u{E134}"
    case aspectRatioFill = "\u{E176}"
    case aspectRatioFillWide = "\u{E177}"
    case aspectRatioWide = "\u{E175}"
    case at = "\u{E01B}"
    case attach = "\u{E058}"
    case audio = "\u{E01C}"
    case audioRectangle = "\u{E178}"
    case audioRectangleFill = "\u{E179}"
    case audioRectangleFillWide = "\u{E17A}"
    case audioRectangleSlash = "\u{E2A3}"
    case audioRectangleSlashFill = "\u{E2A5}"
    case audioRectangleSlashFillWide = "\u{E2A6}"
    case audioRectangleSlashWide = "\u{E2A4}"
    case audioSquare = "\u{E01D}" // symbols.json: audio-rectangle-wide
    case backspace = "\u{E203}"
    case backspaceFill = "\u{E20F}"
    case backspaceFillRTL = "\u{E210}"
    case backspaceRTL = "\u{E17B}"
    case backup = "\u{E09F}"
    case backupError = "\u{E0A0}"
    case backupSignal = "\u{E27E}"
    case badge = "\u{E099}"
    case badgeFill = "\u{E09A}"
    case badgeSet = "\u{E0DA}"
    case badgeSetFill = "\u{E17D}"
    case bear = "\u{E0FE}"
    case bell = "\u{E01E}"
    case bellBadge = "\u{E225}"
    case bellBadgeFill = "\u{E226}"
    case bellBadgeFillRTL = "\u{E304}"
    case bellBadgeRTL = "\u{E303}"
    case bellFill = "\u{E248}"
    case bellRing = "\u{E020}"
    case bellRingFill = "\u{E24A}"
    case bellSlash = "\u{E01F}"
    case bellSlashFill = "\u{E249}"
    case bellSleep = "\u{E0A1}"
    case bellSleepFill = "\u{E24B}"
    case block = "\u{E002}"
    case blur = "\u{E0DB}"
    case blurHeavy = "\u{E247}"
    case blurLight = "\u{E211}"
    case blurMedium = "\u{E212}"
    case bolt = "\u{E0B8}"
    case boltFill = "\u{E218}"
    case boost = "\u{E0E2}"
    case boostFill = "\u{E219}"
    case brushSizeHeavy = "\u{E0DE}"
    case brushSizeMedium = "\u{E0DF}"
    case brushSizeRegular = "\u{E0E0}"
    case brushSizeThin = "\u{E0E1}"
    case building = "\u{E325}"
    case buildingFill = "\u{E326}"
    case calendar = "\u{E0A2}"
    case calendarBlank = "\u{E0A3}"
    case calendarBlankFill = "\u{E2D9}"
    case calendarDay = "\u{E0A5}"
    case calendarDayFill = "\u{E2D7}"
    case calendarDayFillRTL = "\u{E2D8}"
    case calendarDayRTL = "\u{E2D6}"
    case calendarFill = "\u{E2D4}"
    case calendarSearch = "\u{E0E3}"
    case calendarWeek = "\u{E0A4}"
    case calendarWeekFill = "\u{E2D5}"
    case camera = "\u{E0E4}"
    case cameraFill = "\u{E17E}"
    case cameraSwap = "\u{E0E5}"
    case cameraSwapFill = "\u{E17F}"
    case car = "\u{E102}"
    case cellularBars = "\u{E339}"
    case checkCircle = "\u{E022}"
    case checkCircleFill = "\u{E182}"
    case checkCircleOnCheckCircle = "\u{E181}"
    case checkCircleOnCheckCircleFill = "\u{E1FC}"
    case checkCircleOnCheckCircleFillWide = "\u{E047}"
    case checkCircleOnCheckCircleWide = "\u{E046}"
    case checkmark = "\u{E180}" // symbols.json: check
    case checkSquare = "\u{E023}"
    case checkSquareFill = "\u{E183}"
    case chevronCircleDown = "\u{E02B}"
    case chevronCircleDownFill = "\u{E1F5}"
    case chevronCircleLeft = "\u{E028}"
    case chevronCircleLeftFill = "\u{E1F2}"
    case chevronCircleRight = "\u{E029}"
    case chevronCircleRightFill = "\u{E1F3}"
    case chevronCircleUp = "\u{E02A}"
    case chevronCircleUpFill = "\u{E1F4}"
    case chevronDown = "\u{E027}"
    case chevronLeft = "\u{E024}"
    case chevronOutwardLeftRight = "\u{E207}"
    case chevronOutwardUpDown = "\u{E081}"
    case chevronRectangleOutwardUpRightDownLeft = "\u{E2E8}"
    case chevronRectangleOutwardUpRightDownLeftFill = "\u{E2EE}"
    case chevronRectangleOutwardUpRightDownLeftFillWide = "\u{E2EF}"
    case chevronRectangleOutwardUpRightDownLeftWide = "\u{E2E9}"
    case chevronRight = "\u{E025}"
    case chevronShallowDown = "\u{E0E9}"
    case chevronShallowLeft = "\u{E0E6}"
    case chevronShallowRight = "\u{E0E7}"
    case chevronShallowUp = "\u{E0E8}"
    case chevronSquareDown = "\u{E02F}"
    case chevronSquareDownFill = "\u{E1F9}"
    case chevronSquareLeft = "\u{E02C}"
    case chevronSquareLeftFill = "\u{E1F6}"
    case chevronSquareRight = "\u{E02D}"
    case chevronSquareRightFill = "\u{E1F7}"
    case chevronSquareUp = "\u{E02E}"
    case chevronSquareUpFill = "\u{E1F8}"
    case chevronUp = "\u{E026}"
    case circle = "\u{E160}"
    case circleDashed = "\u{E07A}"
    case circleFill = "\u{E184}"
    case clock = "\u{E265}"
    case clockHour1 = "\u{E266}"
    case clockHour10 = "\u{E26F}"
    case clockHour11 = "\u{E270}"
    case clockHour12 = "\u{E271}"
    case clockHour2 = "\u{E267}"
    case clockHour3 = "\u{E268}"
    case clockHour4 = "\u{E269}"
    case clockHour5 = "\u{E26A}"
    case clockHour6 = "\u{E26B}"
    case clockHour7 = "\u{E26C}"
    case clockHour8 = "\u{E26D}"
    case clockHour9 = "\u{E26E}"
    case compose = "\u{E0EA}"
    case connections = "\u{E0AD}"
    case connectionsFill = "\u{E185}"
    case contrast = "\u{E281}"
    case copy = "\u{E0EB}"
    case copyAlt = "\u{E0EC}"
    case creditCard = "\u{E127}"
    case creditCardFill = "\u{E187}"
    case creditCardFillWide = "\u{E188}"
    case creditCardWide = "\u{E186}"
    case crop = "\u{E0ED}"
    case cropLock = "\u{E0EF}"
    case cropRotate = "\u{E0EE}"
    case cropUnlock = "\u{E0F0}"
    case cube = "\u{E221}"
    case cubeBadge = "\u{E223}"
    case cubeBadgeFill = "\u{E224}"
    case cubeBadgeFillRTL = "\u{E324}"
    case cubeBadgeRTL = "\u{E323}"
    case cubeFill = "\u{E222}"
    case deviceLaptop = "\u{E0F4}"
    case deviceLaptopFill = "\u{E18C}"
    case devicePhone = "\u{E0F2}"
    case devicePhoneFill = "\u{E18A}"
    case devicePhoneLaptop = "\u{E112}"
    case devicePhoneLaptopFill = "\u{E252}"
    case deviceTablet = "\u{E0F3}"
    case deviceTabletFill = "\u{E18B}"
    case download = "\u{E0C8}"
    case dragHandle = "\u{E0F5}"
    case dragHandleAlt = "\u{E0F6}"
    case drive = "\u{E288}"
    case driveDown = "\u{E28A}"
    case driveDownFill = "\u{E28B}"
    case driveFill = "\u{E289}"
    case dropper = "\u{E278}"
    case dropperFill = "\u{E279}"
    case edit = "\u{E030}" // symbols.json: pencil
    case emoticon = "\u{E106}"
    case error = "\u{E11A}"
    case errorCircle = "\u{E032}"
    case errorCircleFill = "\u{E093}"
    case errorOctagonFill = "\u{E18F}"
    case errorTriangle = "\u{E092}"
    case errorTriangleFill = "\u{E094}"
    case eyes = "\u{E0FD}"
    case faceAngry = "\u{E0FB}"
    case faceExcited = "\u{E0F9}"
    case faceSad = "\u{E0FA}"
    case faceSmiling = "\u{E18D}"
    case faceSmilingFill = "\u{E18E}"
    case faceSmilingPlus = "\u{E0F8}"
    case faceSmilingPlusWide = "\u{E20C}"
    case file = "\u{E034}"
    case fileFill = "\u{E190}"
    case fileSlash = "\u{E0B1}"
    case fileSlashFill = "\u{E191}"
    case filter = "\u{E107}"
    case filterCircle = "\u{E108}"
    case filterCircleFill = "\u{E1FA}"
    case flag = "\u{E105}"
    case flagFill = "\u{E33D}"
    case flash = "\u{E109}"
    case flashAuto = "\u{E10B}"
    case flashAutoFill = "\u{E194}"
    case flashFill = "\u{E192}"
    case flashSlash = "\u{E10A}"
    case flashSlashFill = "\u{E193}"
    case flip = "\u{E10C}"
    case folder = "\u{E0B2}"
    case folderMinus = "\u{E274}"
    case folderPlus = "\u{E0B3}"
    case folderSettings = "\u{E0B4}"
    case forward = "\u{E035}"
    case forwardFill = "\u{E036}"
    case forwardFillRTL = "\u{E2E2}"
    case forwardRTL = "\u{E2E1}"
    case fullScreen = "\u{E10D}"
    case gif = "\u{E037}"
    case gifRectangle = "\u{E195}"
    case gifRectangleFill = "\u{E196}"
    case gifRectangleFillWide = "\u{E098}"
    case gifRectangleWide = "\u{E097}"
    case gift = "\u{E0B5}"
    case giftFill = "\u{E253}"
    case globe = "\u{E0B6}"
    case globeFill = "\u{E254}"
    case grid = "\u{E10E}"
    case gridFill = "\u{E198}"
    case gridRectangle = "\u{E10F}"
    case gridRectangleFill = "\u{E199}"
    case gridRectangleFillWide = "\u{E19A}"
    case gridRectangleWide = "\u{E197}"
    case gridSidebar = "\u{E13B}"
    case gridSidebarFill = "\u{E23C}"
    case gridSidebarFillWide = "\u{E23D}"
    case gridSidebarWide = "\u{E213}"
    case group = "\u{E19B}"
    case groupFill = "\u{E19D}"
    case groupFillWide = "\u{E19E}"
    case groupQuestion = "\u{E28C}"
    case groupQuestionFill = "\u{E28E}"
    case groupQuestionFillWide = "\u{E28F}"
    case groupQuestionWide = "\u{E28D}"
    case groupWide = "\u{E038}"
    case groupX = "\u{E19C}"
    case groupXFill = "\u{E19F}"
    case groupXFillWide = "\u{E1A0}"
    case groupXInline = "\u{E0AE}" // symbols.json: group-x-wide
    case hd = "\u{E132}"
    case hdFill = "\u{E27C}"
    case hdFillWide = "\u{E27D}"
    case hdSlash = "\u{E133}"
    case hdSlashFill = "\u{E27A}"
    case hdSlashFillWide = "\u{E27B}"
    case hdSlashWide = "\u{E1A2}"
    case hdWide = "\u{E1A1}"
    case headphones = "\u{E110}"
    case headphonesFill = "\u{E1A3}"
    case heart = "\u{E039}"
    case heartFill = "\u{E1A4}"
    case heartPlus = "\u{E0B7}"
    case heartPlusFill = "\u{E1A5}"
    case hexagon = "\u{E2A7}"
    case hexagonFill = "\u{E2A8}"
    case info = "\u{E21A}"
    case infoCircle = "\u{E03B}"
    case infoCircleFill = "\u{E1A7}"
    case invite = "\u{E0B9}"
    case inviteFill = "\u{E2A9}"
    case inviteFillWide = "\u{E2DE}"
    case inviteWide = "\u{E1A8}"
    case key = "\u{E0BA}"
    case keyboard = "\u{E111}"
    case keyboardFill = "\u{E2AA}"
    case keyboardFillWide = "\u{E2AB}"
    case keyboardWide = "\u{E1A9}"
    case keyFill = "\u{E245}"
    case keyHorizontal = "\u{E327}"
    case keyHorizontalFill = "\u{E329}"
    case keyHorizontalFillWide = "\u{E32A}"
    case keyHorizontalWide = "\u{E328}"
    case keySlash = "\u{E0BB}"
    case keySlashFill = "\u{E246}"
    case keyVertical = "\u{E32B}"
    case keyVerticalFill = "\u{E32C}"
    case label = "\u{E27F}"
    case labelFill = "\u{E280}"
    case leaveLTR = "\u{E1AA}" // symbols.json: leave
    case leaveRTL = "\u{E1AB}"
    case lightBulb = "\u{E103}"
    case link = "\u{E03E}"
    case linkAlt = "\u{E03F}"
    case linkBroken = "\u{E057}"
    case linkSlash = "\u{E040}"
    case listBullet = "\u{E113}"
    case listBulletRTL = "\u{E115}"
    case listCircle = "\u{E114}"
    case listCircleRTL = "\u{E116}"
    case location = "\u{E0BC}"
    case locationCircle = "\u{E0BD}"
    case locationCircleFill = "\u{E1AC}"
    case locationFill = "\u{E275}"
    case lock = "\u{E041}"
    case lockFill = "\u{E1AD}"
    case lockOpen = "\u{E07D}"
    case lockOpenFill = "\u{E1AE}"
    case mathSymbolsSquare = "\u{E104}"
    case mathSymbolsSquareFill = "\u{E33F}"
    case megaphone = "\u{E042}"
    case megaphoneFill = "\u{E2AE}"
    case megaphoneFillRTL = "\u{E2E7}"
    case megaphoneRTL = "\u{E2E6}"
    case menu = "\u{E11B}"
    case merge = "\u{E043}"
    case message = "\u{E0A6}"
    case messageArrowForward = "\u{E0A8}"
    case messageArrowForwardFill = "\u{E1B1}"
    case messageArrowForwardFillRTL = "\u{E2ED}"
    case messageArrowForwardRTL = "\u{E2EC}"
    case messageBadge = "\u{E0A7}"
    case messageBadgeFill = "\u{E1B0}"
    case messageBadgeFillRTL = "\u{E2EB}"
    case messageBadgeRTL = "\u{E2EA}"
    case messageCheck = "\u{E0A9}"
    case messageCheckFill = "\u{E1B2}"
    case messageFill = "\u{E1AF}"
    case messageMore = "\u{E0AA}"
    case messageMoreFill = "\u{E1B3}"
    case messageThreadFill = "\u{E072}"
    case messageTimer00 = "\u{E048}" // symbols.json: timer-countdown-0
    case messageTimer05 = "\u{E049}" // symbols.json: timer-countdown-1
    case messageTimer10 = "\u{E04A}" // symbols.json: timer-countdown-2
    case messageTimer15 = "\u{E04B}" // symbols.json: timer-countdown-3
    case messageTimer20 = "\u{E04C}" // symbols.json: timer-countdown-4
    case messageTimer25 = "\u{E04D}" // symbols.json: timer-countdown-5
    case messageTimer30 = "\u{E04E}" // symbols.json: timer-countdown-6
    case messageTimer35 = "\u{E04F}" // symbols.json: timer-countdown-7
    case messageTimer40 = "\u{E050}" // symbols.json: timer-countdown-8
    case messageTimer45 = "\u{E051}" // symbols.json: timer-countdown-9
    case messageTimer50 = "\u{E052}" // symbols.json: timer-countdown-10
    case messageTimer55 = "\u{E053}" // symbols.json: timer-countdown-11
    case messageTimer60 = "\u{E054}" // symbols.json: timer-countdown-12
    case messageX = "\u{E0AB}"
    case messageXFill = "\u{E1B4}"
    case mic = "\u{E055}"
    case micFill = "\u{E1B5}"
    case micSlash = "\u{E056}"
    case micSlashFill = "\u{E1B6}"
    case minus = "\u{E1B7}"
    case minusCircle = "\u{E1B8}"
    case minusCircleFill = "\u{E1B9}"
    case minusSquare = "\u{E059}"
    case minusSquareFill = "\u{E1BA}"
    case missedIncoming = "\u{E05A}"
    case missedOutgoing = "\u{E05B}"
    case moon = "\u{E0BE}"
    case moonFill = "\u{E0D9}"
    case moonSlash = "\u{E209}"
    case moonSlashFill = "\u{E20A}"
    case more = "\u{E120}"
    case moreCircle = "\u{E121}"
    case moreCircleFill = "\u{E208}"
    case moreSquare = "\u{E2D0}"
    case moreSquareFill = "\u{E2D1}"
    case moreVertical = "\u{E2AF}"
    case note = "\u{E095}"
    case noteFill = "\u{E2D2}"
    case noteFillRTL = "\u{E2D3}"
    case noteRTL = "\u{E096}"
    case nothing = "\u{E189}"
    case number = "\u{E0BF}"
    case numberPad = "\u{E123}"
    case numberSquare = "\u{E0C0}"
    case numberSquareFill = "\u{E1BC}"
    case octagon = "\u{E2B0}"
    case octagonFill = "\u{E2B1}"
    case officialBadge = "\u{E086}" // symbols.json: seal-check
    case open = "\u{E0C1}"
    case openRTL = "\u{E23B}"
    case palette = "\u{E0AC}"
    case paletteFill = "\u{E1BD}"
    case pause = "\u{E124}"
    case pauseCircle = "\u{E125}"
    case pauseCircleFill = "\u{E1BF}"
    case pauseFill = "\u{E1BE}"
    case pauseSquare = "\u{E126}"
    case pauseSquareFill = "\u{E1C0}"
    case pencilFill = "\u{E1C1}"
    case person = "\u{E05D}"
    case personBackground = "\u{E2C5}"
    case personBackgroundFill = "\u{E2C6}"
    case personCheck = "\u{E1FE}"
    case personCheckFill = "\u{E255}"
    case personCheckFillWide = "\u{E256}"
    case personCheckWide = "\u{E05F}"
    case personCircle = "\u{E05E}"
    case personCircleFill = "\u{E1C4}"
    case personCirclePlus = "\u{E128}"
    case personCirclePlusRTL = "\u{E321}"
    case personCirclePlusWide = "\u{E2DD}"
    case personCirclePlusWideRTL = "\u{E322}"
    case personFill = "\u{E1C3}"
    case personKey = "\u{E32D}"
    case personKeyFill = "\u{E32F}"
    case personMinus = "\u{E200}"
    case personMinusFill = "\u{E259}"
    case personMinusFillWide = "\u{E25A}"
    case personMinusWide = "\u{E062}"
    case personPlus = "\u{E1FF}"
    case personPlusFill = "\u{E257}"
    case personPlusFillWide = "\u{E258}"
    case personPlusWide = "\u{E061}"
    case personQuestion = "\u{E202}"
    case personQuestionFill = "\u{E25D}"
    case personQuestionFillWide = "\u{E25E}"
    case personQuestionWide = "\u{E06A}"
    case personRectangle = "\u{E12A}"
    case personRectangleFill = "\u{E1C6}"
    case personRectangleFillWide = "\u{E1C7}"
    case personRectangleWide = "\u{E1C2}"
    case personSquare = "\u{E129}"
    case personSquareFill = "\u{E1C5}"
    case personX = "\u{E201}"
    case personXFill = "\u{E25B}"
    case personXFillWide = "\u{E25C}"
    case personXWide = "\u{E060}"
    case phone = "\u{E063}"
    case phoneFill = "\u{E064}"
    case phoneHorizontal = "\u{E12B}"
    case phoneHorizontalFill = "\u{E25F}"
    case phonePlus = "\u{E12C}"
    case phonePlusFill = "\u{E260}"
    case phoneSlash = "\u{E29F}"
    case phoneSlashFill = "\u{E2A0}"
    case phoneSpeaker = "\u{E12D}"
    case phoneSpeakerFill = "\u{E261}"
    case photo = "\u{E1C8}"
    case photoFill = "\u{E290}"
    case photoFillWide = "\u{E291}"
    case photoSlash = "\u{E1C9}"
    case photoSlashFill = "\u{E292}"
    case photoSlashFillWide = "\u{E293}"
    case photoSlashWide = "\u{E066}"
    case photoWide = "\u{E065}"
    case pieChart = "\u{E0F1}"
    case pieChartFill = "\u{E1CA}"
    case pin = "\u{E12E}"
    case pinFill = "\u{E1CB}"
    case pinSlash = "\u{E12F}"
    case pinSlashFill = "\u{E1CC}"
    case pip = "\u{E130}"
    case pipFill = "\u{E23E}"
    case play = "\u{E067}"
    case playCircle = "\u{E068}"
    case playCircleFill = "\u{E1CE}"
    case playFill = "\u{E1CD}"
    case playRectangle = "\u{E1E2}"
    case playRectangleFill = "\u{E1E4}"
    case playRectangleFillWide = "\u{E1E5}"
    case playRectangleSlash = "\u{E1E3}"
    case playRectangleSlashFill = "\u{E1E6}"
    case playRectangleSlashFillWide = "\u{E1E7}"
    case playRectangleSlashWide = "\u{E089}"
    case playRectangleWide = "\u{E088}"
    case playSlash = "\u{E131}"
    case playSlashFill = "\u{E1D0}"
    case playSquare = "\u{E069}"
    case playSquareFill = "\u{E1CF}"
    case plus = "\u{E1D1}"
    case plusCircle = "\u{E1D2}"
    case plusCircleFill = "\u{E1D3}"
    case plusSquare = "\u{E06C}"
    case plusSquareFill = "\u{E1D4}"
    case poll = "\u{E082}"
    case pollFill = "\u{E083}"
    case pollFillRTL = "\u{E273}"
    case pollRTL = "\u{E272}"
    case press = "\u{E14A}"
    case pressFill = "\u{E14B}"
    case qrCode = "\u{E0C2}"
    case question = "\u{E11F}"
    case questionCircle = "\u{E0D8}"
    case questionCircleFill = "\u{E1A6}"
    case raiseHand = "\u{E07E}"
    case raiseHandFill = "\u{E084}"
    case receipt = "\u{E135}"
    case receiptFill = "\u{E2B2}"
    case receiptFillRTL = "\u{E2B3}"
    case receiptRTL = "\u{E136}"
    case recent = "\u{E0C3}"
    case recentFill = "\u{E2B4}"
    case rectangle = "\u{E162}"
    case rectangleDashed = "\u{E214}"
    case rectangleDashedWide = "\u{E215}"
    case rectangleFill = "\u{E1D6}"
    case rectangleFillWide = "\u{E1D7}"
    case rectanglePortrait = "\u{E2B5}"
    case rectanglePortraitDashed = "\u{E2B7}"
    case rectanglePortraitFill = "\u{E2B6}"
    case rectangleWide = "\u{E1D5}"
    case redo = "\u{E0C6}"
    case redoRTL = "\u{E2F6}"
    case refresh = "\u{E0C4}" // symbols.json: arrow-clockwise
    case reply = "\u{E06D}"
    case replyFill = "\u{E06E}"
    case replyFillRTL = "\u{E2F8}"
    case replyRTL = "\u{E2F7}"
    case rotate = "\u{E137}"
    case rotateFill = "\u{E2B8}"
    case safetyNumber = "\u{E06F}" // symbols.json: shield-check
    case scan = "\u{E138}"
    case scanQrCode = "\u{E216}"
    case scribble = "\u{E0F7}"
    case seal = "\u{E2B9}"
    case sealCheckFill = "\u{E087}"
    case sealFill = "\u{E2BA}"
    case search = "\u{E0C7}"
    case securityKey = "\u{E2DF}"
    case securityKeyFill = "\u{E2E0}"
    case send = "\u{E20B}"
    case sendFill = "\u{E0C9}"
    case settings = "\u{E0CA}"
    case settingsAlt = "\u{E0CC}"
    case settingsFill = "\u{E0CB}"
    case share = "\u{E139}"
    case shareAlt = "\u{E13A}"
    case shareScreenFill = "\u{E174}" // symbols.json: arrow-rectangle-up-fill-wide
    case shield = "\u{E2BB}"
    case shieldCheckFill = "\u{E1D8}"
    case shieldError = "\u{E2BD}"
    case shieldErrorFill = "\u{E2BE}"
    case shieldFill = "\u{E2BC}"
    case shieldInfo = "\u{E2BF}"
    case shieldInfoFill = "\u{E2C0}"
    case sidebar = "\u{E13C}"
    case sidebarFill = "\u{E243}"
    case sidebarFillWide = "\u{E244}"
    case sidebarWide = "\u{E217}"
    case signal = "\u{E000}" // not in symbols.json
    case soccerBall = "\u{E101}"
    case soup = "\u{E100}"
    case spam = "\u{E033}" // symbols.json: error-octagon
    case speaker = "\u{E13F}"
    case speakerBluetooth = "\u{E141}"
    case speakerBluetoothFill = "\u{E241}"
    case speakerBluetoothFillRTL = "\u{E2FE}"
    case speakerBluetoothRTL = "\u{E2FD}"
    case speakerFill = "\u{E23F}"
    case speakerFillRTL = "\u{E2FA}"
    case speakerRTL = "\u{E2F9}"
    case speakerSlash = "\u{E142}"
    case speakerSlashFill = "\u{E242}"
    case speakerSlashFillRTL = "\u{E300}"
    case speakerSlashRTL = "\u{E2FF}"
    case speakerX = "\u{E140}"
    case speakerXFill = "\u{E240}"
    case speakerXFillRTL = "\u{E2FC}"
    case speakerXRTL = "\u{E2FB}"
    case square = "\u{E161}"
    case squareDashed = "\u{E17C}"
    case squareFill = "\u{E1FB}"
    case squareOnSquare = "\u{E286}"
    case squareOnSquareFill = "\u{E287}"
    case squareOnSquarePlus = "\u{E122}"
    case squareOnSquarePlusFill = "\u{E1BB}"
    case star = "\u{E0AF}"
    case starFill = "\u{E0B0}"
    case starSlash = "\u{E276}"
    case starSlashFill = "\u{E277}"
    case sticker = "\u{E070}"
    case stickerPack = "\u{E145}"
    case stickerPackPlus = "\u{E146}"
    case stickerSlash = "\u{E144}"
    case stickerSmiley = "\u{E143}"
    case stop = "\u{E147}"
    case stopCircle = "\u{E148}"
    case stopCircleFill = "\u{E1DA}"
    case stopFill = "\u{E1D9}"
    case stopSquare = "\u{E149}"
    case stopSquareFill = "\u{E1DB}"
    case stories = "\u{E0D0}"
    case storiesFill = "\u{E0D1}"
    case sun = "\u{E0D2}"
    case sunFill = "\u{E1DC}"
    case sunHorizon = "\u{E0D3}"
    case sunHorizonFill = "\u{E1DD}"
    case swap = "\u{E0D4}"
    case tada = "\u{E0FF}"
    case textAlignCenter = "\u{E150}"
    case textAlignJustifed = "\u{E152}"
    case textAlignLeft = "\u{E14F}"
    case textAlignRight = "\u{E151}"
    case textEffects = "\u{E153}"
    case textEffectsFill = "\u{E1DF}"
    case textFormatBold = "\u{E154}"
    case textFormatItalic = "\u{E155}"
    case textFormatMonospace = "\u{E157}"
    case textFormatSpoiler = "\u{E158}"
    case textFormatStrikethrough = "\u{E156}"
    case textOutline = "\u{E14E}"
    case textSquare = "\u{E14D}"
    case textSquareFill = "\u{E1DE}"
    case thread = "\u{E071}" // symbols.json: message-thread
    case thumbsDown = "\u{E262}"
    case thumbsDownFill = "\u{E263}"
    case thumbsUp = "\u{E0FC}"
    case thumbsUpFill = "\u{E264}"
    case ticks = "\u{E044}"
    case timer = "\u{E073}"
    case timerFill = "\u{E1E0}"
    case timerSlash = "\u{E074}"
    case timerSlashFill = "\u{E1E1}"
    case trash = "\u{E0D5}"
    case trashFill = "\u{E0D6}"
    case trending = "\u{E159}"
    case trendingRTL = "\u{E301}"
    case triangle = "\u{E2A1}"
    case triangleFill = "\u{E2A2}"
    case tune = "\u{E15A}"
    case typing = "\u{E284}"
    case typingFill = "\u{E285}"
    case undo = "\u{E0C5}"
    case undoRTL = "\u{E302}"
    case upload = "\u{E0D7}"
    case video = "\u{E075}" // symbols.json: videocamera-wide
    case videoCamera = "\u{E1E8}"
    case videoCameraFill = "\u{E1EA}"
    case videoCameraFillWide = "\u{E077}"
    case videoCameraSlash = "\u{E1E9}"
    case videoCameraSlashFill = "\u{E1EB}"
    case videoCameraSlashFillWide = "\u{E1EC}"
    case videoCameraSlashWide = "\u{E076}"
    case viewOnce = "\u{E078}"
    case viewOnceDashed = "\u{E079}"
    case viewOnceSlash = "\u{E204}"
    case visible = "\u{E15B}"
    case visibleFill = "\u{E2CE}"
    case visibleSlash = "\u{E15C}"
    case visibleSlashFill = "\u{E2CF}"
    case wifi = "\u{E15D}"
    case wifiError = "\u{E15E}"
    case x = "\u{E1ED}"
    case xCircle = "\u{E1EE}"
    case xCircleDashed = "\u{E15F}"
    case xCircleFill = "\u{E1F0}"
    case xSquare = "\u{E1EF}"
    case xSquareFill = "\u{E1F1}"
    case zoomIn = "\u{E282}"
    case zoomOut = "\u{E283}"

    // MARK: Localized symbols

    public static var leave: SignalSymbol {
        localizedSymbol(ltr: .leaveLTR, rtl: .leaveRTL)
    }

    /// Use this when adding a trailing chevron to the end of strings we are
    /// localizing ourselves. For names or other user-input text, you might want
    /// to try ``chevronTrailing(for:)`` instead.
    public static var chevronTrailing: SignalSymbol {
        localizedSymbol(ltr: .chevronRight, rtl: .chevronLeft)
    }

    private static func localizedSymbol(ltr: SignalSymbol, rtl: SignalSymbol) -> SignalSymbol {
        CurrentAppContext().isRTL ? rtl : ltr
    }

    private static var stringIsRTLCache: [String: Bool] = [:]
    private static func isRTL(string: String) -> Bool {
        if let isRTL = stringIsRTLCache[string] {
            return isRTL
        }

        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(string)
        let dominantLanguage = languageRecognizer.dominantLanguage

        let isRTL = if let dominantLanguage {
            Locale.characterDirection(forLanguage: dominantLanguage.rawValue) == .rightToLeft
        } else {
            CurrentAppContext().isRTL
        }

        stringIsRTLCache[string] = isRTL
        return isRTL
    }

    /// Use this when adding a chevron to the end of user-input strings like
    /// names. For strings we are localizing ourselves, use ``chevronTrailing``.
    public static func chevronTrailing(for string: String) -> SignalSymbol {
        isRTL(string: string) ? .chevronLeft : .chevronRight
    }

    // MARK: - Font

    public enum Weight {
        case light
        case regular
        case bold
        case medium
        case thin

        fileprivate var fontName: String {
            switch self {
            case .light:
                return "SignalSymbols-Light"
            case .regular:
                return "SignalSymbols-Regular"
            case .bold:
                return "SignalSymbols-Bold"
            case .medium:
                return "SignalSymbols-Medium"
            case .thin:
                return "SignalSymbols-Thin"
            }
        }

        fileprivate func staticFont(ofSize size: CGFloat) -> UIFont {
            UIFont(
                descriptor: UIFontDescriptor(fontAttributes: [
                    .name: self.fontName,
                ]),
                size: size,
            )
        }

        fileprivate func dynamicTypeFont(
            for textStyle: UIFont.TextStyle,
            clamped: Bool,
        ) -> UIFont {
            self.dynamicTypeFont(
                ofStandardSize: UIFont.preferredFont(
                    forTextStyle: textStyle,
                    compatibleWith: UITraitCollection(
                        preferredContentSizeCategory: .large,
                    ),
                ).pointSize,
                clamped: clamped,
            )
        }

        fileprivate func dynamicTypeFont(
            ofStandardSize standardSize: CGFloat,
            clamped: Bool,
        ) -> UIFont {
            let unscaledFont = UIFont(
                descriptor: UIFontDescriptor(fontAttributes: [
                    .name: self.fontName,
                ]),
                size: standardSize,
            )

            if clamped {
                let xxxl = UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge)
                let maxSize = UIFontMetrics.default.scaledValue(for: standardSize, compatibleWith: xxxl)
                return UIFontMetrics.default.scaledFont(for: unscaledFont, maximumPointSize: maxSize)
            }

            return UIFontMetrics.default.scaledFont(
                for: unscaledFont,
            )
        }
    }

    // MARK: - Attributed string

    public enum LeadingCharacter: String {
        case space = " "
        case nonBreakingSpace = "\u{00A0}"
    }

    public func attributedString(
        for textStyle: UIFont.TextStyle,
        clamped: Bool = false,
        weight: Weight = .regular,
        leadingCharacter: LeadingCharacter? = nil,
        attributes: [NSAttributedString.Key: Any] = [:],
    ) -> NSAttributedString {
        self.attributedString(
            font: weight.dynamicTypeFont(
                for: textStyle,
                clamped: clamped,
            ),
            leadingCharacter: leadingCharacter,
            attributes: attributes,
        )
    }

    public func attributedString(
        dynamicTypeBaseSize: CGFloat,
        clamped: Bool = false,
        weight: Weight = .regular,
        leadingCharacter: LeadingCharacter? = nil,
        attributes: [NSAttributedString.Key: Any] = [:],
    ) -> NSAttributedString {
        self.attributedString(
            font: weight.dynamicTypeFont(
                ofStandardSize: dynamicTypeBaseSize,
                clamped: clamped,
            ),
            leadingCharacter: leadingCharacter,
            attributes: attributes,
        )
    }

    public func attributedString(
        staticFontSize: CGFloat,
        weight: Weight = .regular,
        leadingCharacter: LeadingCharacter? = nil,
        attributes: [NSAttributedString.Key: Any] = [:],
    ) -> NSAttributedString {
        self.attributedString(
            font: weight.staticFont(ofSize: staticFontSize),
            leadingCharacter: leadingCharacter,
            attributes: attributes,
        )
    }

    private func attributedString(
        font: UIFont,
        leadingCharacter: LeadingCharacter?,
        attributes: [NSAttributedString.Key: Any],
    ) -> NSAttributedString {
        var attributes = attributes
        attributes[.font] = font

        return NSAttributedString(
            string: "\(leadingCharacter?.rawValue ?? "")\(self.rawValue)",
            attributes: attributes,
        )
    }

    // MARK: - SwiftUI

    /// Creates a SwiftUI `Text` view with the specified dynamic type size and weight.
    ///
    /// Can be combined with other `Text` views with the `+` operator.
    /// For example:
    ///
    /// ```swift
    /// SignalSymbol.arrowUp.text(dynamicTypeBaseSize: 16) +
    /// Text(" Share")
    /// ```
    /// - Parameters:
    ///   - dynamicTypeBaseSize: The base size of the font at 100% Dynamic Type
    ///   scale which will then be scaled based on the current device scale.
    ///   - weight: The font weight.
    /// - Returns: A SwiftUI `Text` view with this symbol and the given font.
    public func text(
        dynamicTypeBaseSize: CGFloat,
        weight: Weight = .regular,
    ) -> Text {
        Text(verbatim: "\(self.rawValue)")
            .font(Font.custom(weight.fontName, size: dynamicTypeBaseSize))
    }
}
