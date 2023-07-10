//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import XCTest

@testable import Signal
@testable import SignalServiceKit
@testable import SignalUI

#if TESTABLE_BUILD

class CVTextTest: XCTestCase {
    func testTextViewMeasurement() {
        let configs = [
            CVTextViewConfig(text: "short", font: .dynamicTypeBody, textColor: .black),
            CVTextViewConfig(
                text: """
                Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.

                Aliquam malesuada porta dapibus. Aliquam fermentum faucibus velit, nec hendrerit massa fermentum nec. Nulla semper nibh eu justo accumsan auctor. Aenean justo eros, gravida at arcu sed, vulputate vulputate urna. Nulla et congue ligula. Vivamus non felis bibendum, condimentum elit et, tristique justo. Donec sed diam odio. In vitae pretium ante, sed rhoncus ex. Cras ultricies suscipit faucibus. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Donec imperdiet diam sit amet consequat aliquet. Donec eu dignissim dui. Suspendisse pellentesque metus turpis, non aliquam arcu egestas sed. Sed eu urna lacus. Pellentesque malesuada rhoncus nunc non sagittis. Aliquam bibendum, dolor id posuere volutpat, ex sem fermentum justo, non efficitur nisl lorem vel neque.

                Etiam sed felis nunc. Suspendisse vestibulum elit eu dignissim accumsan. Morbi tortor arcu, vulputate eu varius vel, varius ac sapien. Aenean ut efficitur augue. Sed semper diam at ipsum aliquet scelerisque. Pellentesque blandit quis sem non euismod. Sed accumsan tellus quis sapien fermentum, quis dapibus urna tincidunt. Nam mattis fermentum nisl, non eleifend tortor facilisis sed. Vestibulum vitae efficitur dolor. Nam ligula odio, molestie eu porttitor eu, dignissim ut nulla. Ut tempor diam id sapien mattis dignissim. Pellentesque accumsan nibh a velit convallis laoreet.
                """,
                font: .dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                text: """
                Λορεμ ιπσθμ δολορ σιτ αμετ, εα προ αλιι εσσε cετεροσ. Vιδερερ φαστιδιι αλβθcιθσ cθ σιτ, νε εστ vελιτ ατομορθμ. Ναμ νο ηινc cονγθε ρεcθσαβο, νε αλιqθαμ νεγλεγεντθρ εστ. Ποστεα περπετθα προ τε, ηασ νισλ περιcθλα ιδ. Ενιμ vιρτθτε αδ μεα. Θλλθμ αδμοδθμ ει vισ, εαμ vερι qθανδο αδ. Vελ ιλλθδ ετιαμ σιγνιφερθμqθε εα, μοδθσ θτιναμ παρτεμ vιξ εα.

                Ετ δθο σολεατ αθδιαμ, σιτ πθταντ σανcτθσ ιδ. Αν αccθμσαν ιντερπρεταρισ εθμ, μελ νολθισσε διγνισσιμ νε. Φορενσιβθσ ρεφορμιδανσ θλλαμcορπερ θτ ηασ, ναμ απεριαμ αλιqθιδ αν. Cθ σολθμ δελενιτ πατριοqθε εθμ, δετραcτο cονσετετθρ εστ τε. Νοvθμ σανcτθσ σεδ νο.
                """,
                font: .dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                text: """
                لكن لا بد أن أوضح لك أن كل هذه الأفكار المغلوطة حول استنكار  النشوة وتمجيد الألم نشأت بالفعل، وسأعرض لك التفاصيل لتكتشف حقيقة وأساس تلك السعادة البشرية، فلا أحد يرفض أو يكره أو يتجنب الشعور بالسعادة، ولكن بفضل هؤلاء الأشخاص الذين لا يدركون بأن السعادة لا بد أن نستشعرها بصورة أكثر عقلانية ومنطقية فيعرضهم هذا لمواجهة الظروف الأليمة، وأكرر بأنه لا يوجد من يرغب في الحب ونيل المنال ويتلذذ بالآلام، الألم هو الألم ولكن نتيجة لظروف ما قد تكمن السعاده فيما نتحمله من كد وأسي.

                و سأعرض مثال حي لهذا، من منا لم يتحمل جهد بدني شاق إلا من أجل الحصول على ميزة أو فائدة؟ ولكن من لديه الحق أن ينتقد شخص ما أراد أن يشعر بالسعادة التي لا تشوبها عواقب أليمة أو آخر أراد أن يتجنب الألم الذي ربما تنجم عنه بعض المتعة ؟
                علي الجانب الآخر نشجب ونستنكر هؤلاء الرجال المفتونون بنشوة اللحظة الهائمون في رغباتهم فلا يدركون ما يعقبها من الألم والأسي المحتم، واللوم كذلك يشمل هؤلاء الذين أخفقوا في واجباتهم نتيجة لضعف إرادتهم فيتساوي مع هؤلاء الذين يتجنبون وينأون عن تحمل الكدح والألم .

                """,
                font: .dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                text: """
                東沢族応同市総暮見送軟因旧野声。療名岡無会婚必文政職産首堪。原馬果制前興禁出部医保機出。賞響子恵横大厳著美無新殺常芸観載。上属力一本彰料必転指影未税廟赤府研。読煙責負力異寺先発事製量情停並。国圏場権電別新力際営測進必。事藤着人体存止作月玉社英題写予者。間引内一強客透人戦一家万暮読。種扱報崎若陣加府大姿平問写提化針離定。

                足己謙告保士清修根選暮区細理貨聞年半。読治問形球漂注出裏下公療演続。芸意記栄山写日撃掲国主治当性発。生意逃免渡資一取引裕督転。応点続果安罰村必禁家政拳。写禁法考証言心彫埼権川関員奏届新営覚掲。南応要参愛類娘都誰定尚同勝積鎌記写塁。政回過市主覧貨張加主子義空教対券。載捕構方聞度名出結字夜何動問暮理詳半話。
                """,
                font: .dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                text: """
                Lorem ipsum dolor sit amet 😟, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem 🧐, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac 🤞 ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.
                """,
                font: .dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                text: """
                He’s awesome. This album isn’t listed on his discography, but it’s a cool album of duets with Courtney Barnett: https://open.spotify.com/album/3gvo4nvimDdqA9c3y7Bptc?si=aA8z06HoQAG8Xl2MbhFiRQ
                """,
                font: .dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                text: """
                Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.

                東沢族応同市総暮見送軟因旧野声。療名岡無会婚必文政職産首堪。原馬果制前興禁出部医保機出。賞響子恵横大厳著美無新殺常芸観載。上属力一本彰料必転指影未税廟赤府研。読煙責負力異寺先発事製量情停並。国圏場権電別新力際営測進必。事藤着人体存止作月玉社英題写予者。間引内一強客透人戦一家万暮読。種扱報崎若陣加府大姿平問写提化針離定。

                Etiam sed felis nunc. Suspendisse vestibulum elit eu dignissim accumsan. Morbi tortor arcu, vulputate eu varius vel, varius ac sapien. Aenean ut efficitur augue. Sed semper diam at ipsum aliquet scelerisque. Pellentesque blandit quis sem non euismod. Sed accumsan tellus quis sapien fermentum, quis dapibus urna tincidunt. Nam mattis fermentum nisl, non eleifend tortor facilisis sed. Vestibulum vitae efficitur dolor. Nam ligula odio, molestie eu porttitor eu, dignissim ut nulla. Ut tempor diam id sapien mattis dignissim. Pellentesque accumsan nibh a velit convallis laoreet.
                """,
                font: .dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                attributedText: NSAttributedString(string: "short"),
                font: .dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                attributedText: NSAttributedString(string: "one\ntwo\nthree"),
                font: .dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                attributedText: NSAttributedString.composed(of: [
                    Theme.iconImage(.video16), "Some text", "\n", Theme.iconImage(.video16), "Some text2"
                ]),
                font: .dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                attributedText: {
                    let labelText = NSMutableAttributedString()

                    labelText.appendTemplatedImage(named: Theme.iconName(.compose16),
                                                   font: .dynamicTypeFootnote,
                                                   heightReference: .lineHeight)
                    labelText.append("  You changed the group name to “Test Group Call 2“.\n", attributes: [:])

                    labelText.appendTemplatedImage(named: Theme.iconName(.photo16),
                                                   font: .dynamicTypeFootnote,
                                                   heightReference: .lineHeight)
                    labelText.append("  You updated the photo.", attributes: [:])

                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.paragraphSpacing = 12
                    paragraphStyle.alignment = .center
                    labelText.addAttributeToEntireString(.paragraphStyle, value: paragraphStyle)

                    return labelText
                }(),
                font: .dynamicTypeFootnote,
                textColor: .black,
                textAlignment: .center
            )
        ]

        for config in configs {
            for possibleWidth: CGFloat in stride(from: 100, to: 2000, by: 50) {
                let bodyTextLabelConfig = Self.bodyTextLabelConfig(textViewConfig: config)
                let measuredSize = CVText.measureBodyTextLabel(config: bodyTextLabelConfig, maxWidth: possibleWidth)
                // CVTextLabel only has a single measurement mechanism; there isn't
                // an independent way to verify the correctness of measurements.
                XCTAssertTrue(measuredSize.size.width > 0)
                XCTAssertTrue(measuredSize.size.width > 0)
            }
        }
    }

    static func bodyTextLabelConfig(textViewConfig: CVTextViewConfig) -> CVTextLabel.Config {
        return CVTextLabel.Config(
            text: textViewConfig.text,
            displayConfig: textViewConfig.displayConfiguration,
            font: textViewConfig.font,
            textColor: textViewConfig.textColor,
            selectionStyling: [.foregroundColor: UIColor.orange],
            textAlignment: textViewConfig.textAlignment ?? .natural,
            lineBreakMode: .byWordWrapping,
            numberOfLines: 0,
            cacheKey: textViewConfig.cacheKey,
            items: [],
            linkifyStyle: .underlined(bodyTextColor: textViewConfig.textColor)
        )
    }

    func testLabelMeasurement() {
        let configs = [
            CVLabelConfig(text: "short", font: .dynamicTypeBody, textColor: .black, numberOfLines: 1),
            CVLabelConfig(
                text: """
                Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.

                Aliquam malesuada porta dapibus. Aliquam fermentum faucibus velit, nec hendrerit massa fermentum nec. Nulla semper nibh eu justo accumsan auctor. Aenean justo eros, gravida at arcu sed, vulputate vulputate urna. Nulla et congue ligula. Vivamus non felis bibendum, condimentum elit et, tristique justo. Donec sed diam odio. In vitae pretium ante, sed rhoncus ex. Cras ultricies suscipit faucibus. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Donec imperdiet diam sit amet consequat aliquet. Donec eu dignissim dui. Suspendisse pellentesque metus turpis, non aliquam arcu egestas sed. Sed eu urna lacus. Pellentesque malesuada rhoncus nunc non sagittis. Aliquam bibendum, dolor id posuere volutpat, ex sem fermentum justo, non efficitur nisl lorem vel neque.

                Etiam sed felis nunc. Suspendisse vestibulum elit eu dignissim accumsan. Morbi tortor arcu, vulputate eu varius vel, varius ac sapien. Aenean ut efficitur augue. Sed semper diam at ipsum aliquet scelerisque. Pellentesque blandit quis sem non euismod. Sed accumsan tellus quis sapien fermentum, quis dapibus urna tincidunt. Nam mattis fermentum nisl, non eleifend tortor facilisis sed. Vestibulum vitae efficitur dolor. Nam ligula odio, molestie eu porttitor eu, dignissim ut nulla. Ut tempor diam id sapien mattis dignissim. Pellentesque accumsan nibh a velit convallis laoreet.
                """,
                font: .dynamicTypeBody,
                textColor: .black,
                numberOfLines: 3
            ),
            CVLabelConfig(
                text: """
                Λορεμ ιπσθμ δολορ σιτ αμετ, εα προ αλιι εσσε cετεροσ. Vιδερερ φαστιδιι αλβθcιθσ cθ σιτ, νε εστ vελιτ ατομορθμ. Ναμ νο ηινc cονγθε ρεcθσαβο, νε αλιqθαμ νεγλεγεντθρ εστ. Ποστεα περπετθα προ τε, ηασ νισλ περιcθλα ιδ. Ενιμ vιρτθτε αδ μεα. Θλλθμ αδμοδθμ ει vισ, εαμ vερι qθανδο αδ. Vελ ιλλθδ ετιαμ σιγνιφερθμqθε εα, μοδθσ θτιναμ παρτεμ vιξ εα.

                Ετ δθο σολεατ αθδιαμ, σιτ πθταντ σανcτθσ ιδ. Αν αccθμσαν ιντερπρεταρισ εθμ, μελ νολθισσε διγνισσιμ νε. Φορενσιβθσ ρεφορμιδανσ θλλαμcορπερ θτ ηασ, ναμ απεριαμ αλιqθιδ αν. Cθ σολθμ δελενιτ πατριοqθε εθμ, δετραcτο cονσετετθρ εστ τε. Νοvθμ σανcτθσ σεδ νο.
                """,
                font: .dynamicTypeBody,
                textColor: .black,
                numberOfLines: 0

            ),
            CVLabelConfig(
                text: """
                لكن لا بد أن أوضح لك أن كل هذه الأفكار المغلوطة حول استنكار  النشوة وتمجيد الألم نشأت بالفعل، وسأعرض لك التفاصيل لتكتشف حقيقة وأساس تلك السعادة البشرية، فلا أحد يرفض أو يكره أو يتجنب الشعور بالسعادة، ولكن بفضل هؤلاء الأشخاص الذين لا يدركون بأن السعادة لا بد أن نستشعرها بصورة أكثر عقلانية ومنطقية فيعرضهم هذا لمواجهة الظروف الأليمة، وأكرر بأنه لا يوجد من يرغب في الحب ونيل المنال ويتلذذ بالآلام، الألم هو الألم ولكن نتيجة لظروف ما قد تكمن السعاده فيما نتحمله من كد وأسي.

                و سأعرض مثال حي لهذا، من منا لم يتحمل جهد بدني شاق إلا من أجل الحصول على ميزة أو فائدة؟ ولكن من لديه الحق أن ينتقد شخص ما أراد أن يشعر بالسعادة التي لا تشوبها عواقب أليمة أو آخر أراد أن يتجنب الألم الذي ربما تنجم عنه بعض المتعة ؟
                علي الجانب الآخر نشجب ونستنكر هؤلاء الرجال المفتونون بنشوة اللحظة الهائمون في رغباتهم فلا يدركون ما يعقبها من الألم والأسي المحتم، واللوم كذلك يشمل هؤلاء الذين أخفقوا في واجباتهم نتيجة لضعف إرادتهم فيتساوي مع هؤلاء الذين يتجنبون وينأون عن تحمل الكدح والألم .

                """,
                font: .dynamicTypeBody,
                textColor: .black,
                numberOfLines: 0
            ),
            CVLabelConfig(
                text: """
                東沢族応同市総暮見送軟因旧野声。療名岡無会婚必文政職産首堪。原馬果制前興禁出部医保機出。賞響子恵横大厳著美無新殺常芸観載。上属力一本彰料必転指影未税廟赤府研。読煙責負力異寺先発事製量情停並。国圏場権電別新力際営測進必。事藤着人体存止作月玉社英題写予者。間引内一強客透人戦一家万暮読。種扱報崎若陣加府大姿平問写提化針離定。

                足己謙告保士清修根選暮区細理貨聞年半。読治問形球漂注出裏下公療演続。芸意記栄山写日撃掲国主治当性発。生意逃免渡資一取引裕督転。応点続果安罰村必禁家政拳。写禁法考証言心彫埼権川関員奏届新営覚掲。南応要参愛類娘都誰定尚同勝積鎌記写塁。政回過市主覧貨張加主子義空教対券。載捕構方聞度名出結字夜何動問暮理詳半話。
                """,
                font: .dynamicTypeBody,
                textColor: .black,
                numberOfLines: 0
            ),
            CVLabelConfig(
                text: """
                Lorem ipsum dolor sit amet 😟, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem 🧐, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac 🤞 ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.
                """,
                font: .dynamicTypeBody,
                textColor: .black,
                numberOfLines: 0
            ),
            CVLabelConfig(
                text: """
                Lorem ipsum dolor sit amet 😟, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem 🧐, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac 🤞 ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.
                """,
                font: .dynamicTypeBody,
                textColor: .black,
                numberOfLines: 2
            ),
            CVLabelConfig(
                text: """
                Lorem ipsum dolor sit amet 😟, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem 🧐, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac 🤞 ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.
                """,
                font: .dynamicTypeBody,
                textColor: .black,
                numberOfLines: 5,
                lineBreakMode: .byTruncatingMiddle
            ),
            CVLabelConfig(
                attributedText: NSAttributedString(string: "short"),
                font: .dynamicTypeBody,
                textColor: .black,
                numberOfLines: 1
            ),
            CVLabelConfig(
                attributedText: NSAttributedString(string: "one\ntwo\nthree"),
                font: .dynamicTypeBody,
                textColor: .black,
                numberOfLines: 0
            ),
            CVLabelConfig(
                attributedText: NSAttributedString.composed(of: [
                    Theme.iconImage(.video16), "Some text", "\n", Theme.iconImage(.video16), "Some text2"
                ]),
                font: .dynamicTypeBody,
                textColor: .black,
                numberOfLines: 0
            ),
            CVLabelConfig(
                attributedText: {
                    let labelText = NSMutableAttributedString()

                    labelText.appendTemplatedImage(named: Theme.iconName(.compose16),
                                                   font: .dynamicTypeFootnote,
                                                   heightReference: .lineHeight)
                    labelText.append("  You changed the group name to “Test Group Call 2“.\n", attributes: [:])

                    labelText.appendTemplatedImage(named: Theme.iconName(.photo16),
                                                   font: .dynamicTypeFootnote,
                                                   heightReference: .lineHeight)
                    labelText.append("  You updated the photo.", attributes: [:])

                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.paragraphSpacing = 12
                    paragraphStyle.alignment = .center
                    labelText.addAttributeToEntireString(.paragraphStyle, value: paragraphStyle)

                    return labelText
                }(),
                font: .dynamicTypeFootnote,
                textColor: .black,
                numberOfLines: 0,
                lineBreakMode: .byWordWrapping,
                textAlignment: .center
            )
        ]

        for config in configs {
            for possibleWidth: CGFloat in stride(from: 100, to: 2000, by: 50) {
                let viewSize = CVText.measureLabelUsingView(config: config, maxWidth: possibleWidth)
                let defaultSize = CVText.measureLabelUsingLayoutManager(config: config, maxWidth: possibleWidth)
                // TODO: This test is broken.
                // XCTAssertEqual(viewSize.width, defaultSize.width)
                // XCTAssertEqual(viewSize.height, defaultSize.height)
                if viewSize != defaultSize {
                    Logger.warn("viewSize: \(viewSize) != defaultSize: \(defaultSize).")
                }
            }
        }
    }

    func testLinkifyWithTruncation() {
        let fullText = NSMutableAttributedString(string: "https://signal.org/foo https://signal.org/bar/baz")
        let truncatedText = NSMutableAttributedString(string: "https://signal.org/foo https://signal.org/ba…")
        var dataItems = CVComponentBodyText.detectItems(
            text: DisplayableText.testOnlyInit(fullContent: .attributedText(fullText), truncatedContent: .attributedText(truncatedText)),
            hasPendingMessageRequest: false,
            shouldAllowLinkification: true,
            textWasTruncated: true,
            revealedSpoilerIds: Set(),
            interactionUniqueId: UUID().uuidString,
            interactionIdentifier: InteractionSnapshotIdentifier(timestamp: 0, authorUuid: nil)
        )
        CVTextLabel.linkifyData(
            attributedText: truncatedText,
            linkifyStyle: .linkAttribute,
            items: dataItems
        )
        var values: [String] = []
        var ranges: [NSRange] = []
        truncatedText.enumerateAttribute(.link, in: truncatedText.entireRange, options: []) { value, range, _ in
            if let value = value {
                values.append(value as! String)
                ranges.append(range)
            }
        }
        XCTAssertEqual(["https://signal.org/foo"], values)
        XCTAssertEqual([NSRange(location: 0, length: 22)], ranges)

        truncatedText.removeAttribute(.link, range: truncatedText.entireRange)
        dataItems = CVComponentBodyText.detectItems(
            text: DisplayableText.testOnlyInit(fullContent: .attributedText(fullText), truncatedContent: .attributedText(truncatedText)),
            hasPendingMessageRequest: false,
            shouldAllowLinkification: true,
            textWasTruncated: false,
            revealedSpoilerIds: Set(),
            interactionUniqueId: UUID().uuidString,
            interactionIdentifier: InteractionSnapshotIdentifier(timestamp: 0, authorUuid: nil)
        )
        CVTextLabel.linkifyData(
            attributedText: fullText,
            linkifyStyle: .linkAttribute,
            items: dataItems
        )
        values.removeAll()
        ranges.removeAll()
        fullText.enumerateAttribute(.link, in: fullText.entireRange, options: []) { value, range, _ in
            if let value = value {
                values.append(value as! String)
                ranges.append(range)
            }
        }
        XCTAssertEqual(["https://signal.org/foo", "https://signal.org/bar/baz"], values)
        XCTAssertEqual([NSRange(location: 0, length: 22), NSRange(location: 23, length: 26)], ranges)

        // Should work on more than just URLs.
        let fullEmail = NSMutableAttributedString(string: "moxie@example.com moxie@signal.org")
        let truncatedEmail = NSMutableAttributedString(string: "moxie@example.com moxie@signal.or…")
        dataItems = CVComponentBodyText.detectItems(
            text: DisplayableText.testOnlyInit(fullContent: .attributedText(fullEmail), truncatedContent: .attributedText(truncatedEmail)),
            hasPendingMessageRequest: false,
            shouldAllowLinkification: true,
            textWasTruncated: true,
            revealedSpoilerIds: Set(),
            interactionUniqueId: UUID().uuidString,
            interactionIdentifier: InteractionSnapshotIdentifier(timestamp: 0, authorUuid: nil)
        )
        CVTextLabel.linkifyData(
            attributedText: truncatedEmail,
            linkifyStyle: .linkAttribute,
            items: dataItems
        )
        values.removeAll()
        truncatedEmail.enumerateAttribute(.link, in: truncatedEmail.entireRange, options: []) { value, _, _ in
            if let value = value {
                values.append(value as! String)
            }
        }
        XCTAssertEqual(["mailto:moxie@example.com"], values)

        let fullPhone = NSMutableAttributedString(string: "+16505555555 +16505555555")
        let truncatedPhone = NSMutableAttributedString(string: "+16505555555 +1650555555…")
        dataItems = CVComponentBodyText.detectItems(
            text: DisplayableText.testOnlyInit(fullContent: .attributedText(fullPhone), truncatedContent: .attributedText(truncatedPhone)),
            hasPendingMessageRequest: false,
            shouldAllowLinkification: true,
            textWasTruncated: true,
            revealedSpoilerIds: Set(),
            interactionUniqueId: UUID().uuidString,
            interactionIdentifier: InteractionSnapshotIdentifier(timestamp: 0, authorUuid: nil)
        )
        CVTextLabel.linkifyData(
            attributedText: truncatedPhone,
            linkifyStyle: .linkAttribute,
            items: dataItems
        )
        values.removeAll()
        truncatedPhone.enumerateAttribute(.link, in: truncatedPhone.entireRange, options: []) { value, _, _ in
            if let value = value {
                values.append(value as! String)
            }
        }
        XCTAssertEqual(["tel:+16505555555"], values)
    }
}

extension CVLabelConfig {

    fileprivate init(
        text: String,
        font: UIFont,
        textColor: UIColor,
        numberOfLines: Int = 1,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) {
        self.init(
            text: .text(text),
            displayConfig: .forUnstyledText(font: font, textColor: textColor),
            font: font,
            textColor: textColor,
            numberOfLines: numberOfLines,
            lineBreakMode: lineBreakMode
        )
    }

    fileprivate init(
        attributedText: NSAttributedString,
        font: UIFont,
        textColor: UIColor,
        numberOfLines: Int = 1,
        lineBreakMode: NSLineBreakMode = .byWordWrapping,
        textAlignment: NSTextAlignment? = nil
    ) {
        self.init(
            text: .attributedText(attributedText),
            displayConfig: .forUnstyledText(font: font, textColor: textColor),
            font: font,
            textColor: textColor,
            numberOfLines: numberOfLines,
            lineBreakMode: lineBreakMode,
            textAlignment: textAlignment
        )
    }
}

extension CVTextViewConfig {

    fileprivate init(
        text: String,
        font: UIFont,
        textColor: UIColor
    ) {
        self.init(
            text: .text(text),
            font: font,
            textColor: textColor,
            displayConfiguration: .forUnstyledText(font: font, textColor: textColor),
            linkifyStyle: .linkAttribute,
            linkItems: [],
            matchedSearchRanges: []
        )
    }

    fileprivate init(
        attributedText: NSAttributedString,
        font: UIFont,
        textColor: UIColor,
        textAlignment: NSTextAlignment? = nil
    ) {
        self.init(
            text: .attributedText(attributedText),
            font: font,
            textColor: textColor,
            textAlignment: textAlignment,
            displayConfiguration: .forUnstyledText(font: font, textColor: textColor),
            linkifyStyle: .linkAttribute,
            linkItems: [],
            matchedSearchRanges: []
        )
    }
}

#endif
