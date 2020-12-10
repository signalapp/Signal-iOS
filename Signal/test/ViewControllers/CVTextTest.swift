//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
@testable import Signal

class CVTextTest: SignalBaseTest {
    func testTextViewMeasurement() {
        let configs = [
            CVTextViewConfig(text: "short", font: .ows_dynamicTypeBody, textColor: .black),
            CVTextViewConfig(
                text: """
                Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.

                Aliquam malesuada porta dapibus. Aliquam fermentum faucibus velit, nec hendrerit massa fermentum nec. Nulla semper nibh eu justo accumsan auctor. Aenean justo eros, gravida at arcu sed, vulputate vulputate urna. Nulla et congue ligula. Vivamus non felis bibendum, condimentum elit et, tristique justo. Donec sed diam odio. In vitae pretium ante, sed rhoncus ex. Cras ultricies suscipit faucibus. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Donec imperdiet diam sit amet consequat aliquet. Donec eu dignissim dui. Suspendisse pellentesque metus turpis, non aliquam arcu egestas sed. Sed eu urna lacus. Pellentesque malesuada rhoncus nunc non sagittis. Aliquam bibendum, dolor id posuere volutpat, ex sem fermentum justo, non efficitur nisl lorem vel neque.

                Etiam sed felis nunc. Suspendisse vestibulum elit eu dignissim accumsan. Morbi tortor arcu, vulputate eu varius vel, varius ac sapien. Aenean ut efficitur augue. Sed semper diam at ipsum aliquet scelerisque. Pellentesque blandit quis sem non euismod. Sed accumsan tellus quis sapien fermentum, quis dapibus urna tincidunt. Nam mattis fermentum nisl, non eleifend tortor facilisis sed. Vestibulum vitae efficitur dolor. Nam ligula odio, molestie eu porttitor eu, dignissim ut nulla. Ut tempor diam id sapien mattis dignissim. Pellentesque accumsan nibh a velit convallis laoreet.
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                text: """
                Λορεμ ιπσθμ δολορ σιτ αμετ, εα προ αλιι εσσε cετεροσ. Vιδερερ φαστιδιι αλβθcιθσ cθ σιτ, νε εστ vελιτ ατομορθμ. Ναμ νο ηινc cονγθε ρεcθσαβο, νε αλιqθαμ νεγλεγεντθρ εστ. Ποστεα περπετθα προ τε, ηασ νισλ περιcθλα ιδ. Ενιμ vιρτθτε αδ μεα. Θλλθμ αδμοδθμ ει vισ, εαμ vερι qθανδο αδ. Vελ ιλλθδ ετιαμ σιγνιφερθμqθε εα, μοδθσ θτιναμ παρτεμ vιξ εα.

                Ετ δθο σολεατ αθδιαμ, σιτ πθταντ σανcτθσ ιδ. Αν αccθμσαν ιντερπρεταρισ εθμ, μελ νολθισσε διγνισσιμ νε. Φορενσιβθσ ρεφορμιδανσ θλλαμcορπερ θτ ηασ, ναμ απεριαμ αλιqθιδ αν. Cθ σολθμ δελενιτ πατριοqθε εθμ, δετραcτο cονσετετθρ εστ τε. Νοvθμ σανcτθσ σεδ νο.
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                text: """
                東沢族応同市総暮見送軟因旧野声。療名岡無会婚必文政職産首堪。原馬果制前興禁出部医保機出。賞響子恵横大厳著美無新殺常芸観載。上属力一本彰料必転指影未税廟赤府研。読煙責負力異寺先発事製量情停並。国圏場権電別新力際営測進必。事藤着人体存止作月玉社英題写予者。間引内一強客透人戦一家万暮読。種扱報崎若陣加府大姿平問写提化針離定。

                足己謙告保士清修根選暮区細理貨聞年半。読治問形球漂注出裏下公療演続。芸意記栄山写日撃掲国主治当性発。生意逃免渡資一取引裕督転。応点続果安罰村必禁家政拳。写禁法考証言心彫埼権川関員奏届新営覚掲。南応要参愛類娘都誰定尚同勝積鎌記写塁。政回過市主覧貨張加主子義空教対券。載捕構方聞度名出結字夜何動問暮理詳半話。
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                text: """
                Lorem ipsum dolor sit amet 😟, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem 🧐, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac 🤞 ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                text: """
                He’s awesome. This album isn’t listed on his discography, but it’s a cool album of duets with Courtney Barnett: https://open.spotify.com/album/3gvo4nvimDdqA9c3y7Bptc?si=aA8z06HoQAG8Xl2MbhFiRQ
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black
            ),
            CVTextViewConfig(
                text: """
                Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.

                東沢族応同市総暮見送軟因旧野声。療名岡無会婚必文政職産首堪。原馬果制前興禁出部医保機出。賞響子恵横大厳著美無新殺常芸観載。上属力一本彰料必転指影未税廟赤府研。読煙責負力異寺先発事製量情停並。国圏場権電別新力際営測進必。事藤着人体存止作月玉社英題写予者。間引内一強客透人戦一家万暮読。種扱報崎若陣加府大姿平問写提化針離定。

                Etiam sed felis nunc. Suspendisse vestibulum elit eu dignissim accumsan. Morbi tortor arcu, vulputate eu varius vel, varius ac sapien. Aenean ut efficitur augue. Sed semper diam at ipsum aliquet scelerisque. Pellentesque blandit quis sem non euismod. Sed accumsan tellus quis sapien fermentum, quis dapibus urna tincidunt. Nam mattis fermentum nisl, non eleifend tortor facilisis sed. Vestibulum vitae efficitur dolor. Nam ligula odio, molestie eu porttitor eu, dignissim ut nulla. Ut tempor diam id sapien mattis dignissim. Pellentesque accumsan nibh a velit convallis laoreet.
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black
            )
        ]

        for config in configs {
            for possibleWidth: CGFloat in stride(from: 100, to: 2000, by: 50) {
                let viewSize = CVText.measureTextView(mode: .view, config: config, maxWidth: possibleWidth)
                let defaultSize = CVText.measureTextView(config: config, maxWidth: possibleWidth)
                XCTAssertEqual(viewSize.width, defaultSize.width)

                if config.containsCJKCharacters {
                    // TODO: In rare instances, measurement of CJK can be off by a lot, but
                    // always in the "too big" direction, so nothing will clip. We should try
                    // and fix this, but in simple cases it generally seems OK.
                    XCTAssertLessThanOrEqual(viewSize.height, defaultSize.height)
                } else {
                    XCTAssertEqual(viewSize.height, defaultSize.height)
                }
            }
        }
    }

    func testLabelMeasurement() {
        let configs = [
            CVLabelConfig(text: "short", font: .ows_dynamicTypeBody, textColor: .black, numberOfLines: 1),
            CVLabelConfig(
                text: """
                Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.

                Aliquam malesuada porta dapibus. Aliquam fermentum faucibus velit, nec hendrerit massa fermentum nec. Nulla semper nibh eu justo accumsan auctor. Aenean justo eros, gravida at arcu sed, vulputate vulputate urna. Nulla et congue ligula. Vivamus non felis bibendum, condimentum elit et, tristique justo. Donec sed diam odio. In vitae pretium ante, sed rhoncus ex. Cras ultricies suscipit faucibus. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Donec imperdiet diam sit amet consequat aliquet. Donec eu dignissim dui. Suspendisse pellentesque metus turpis, non aliquam arcu egestas sed. Sed eu urna lacus. Pellentesque malesuada rhoncus nunc non sagittis. Aliquam bibendum, dolor id posuere volutpat, ex sem fermentum justo, non efficitur nisl lorem vel neque.

                Etiam sed felis nunc. Suspendisse vestibulum elit eu dignissim accumsan. Morbi tortor arcu, vulputate eu varius vel, varius ac sapien. Aenean ut efficitur augue. Sed semper diam at ipsum aliquet scelerisque. Pellentesque blandit quis sem non euismod. Sed accumsan tellus quis sapien fermentum, quis dapibus urna tincidunt. Nam mattis fermentum nisl, non eleifend tortor facilisis sed. Vestibulum vitae efficitur dolor. Nam ligula odio, molestie eu porttitor eu, dignissim ut nulla. Ut tempor diam id sapien mattis dignissim. Pellentesque accumsan nibh a velit convallis laoreet.
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black,
                numberOfLines: 3
            ),
            CVLabelConfig(
                text: """
                Λορεμ ιπσθμ δολορ σιτ αμετ, εα προ αλιι εσσε cετεροσ. Vιδερερ φαστιδιι αλβθcιθσ cθ σιτ, νε εστ vελιτ ατομορθμ. Ναμ νο ηινc cονγθε ρεcθσαβο, νε αλιqθαμ νεγλεγεντθρ εστ. Ποστεα περπετθα προ τε, ηασ νισλ περιcθλα ιδ. Ενιμ vιρτθτε αδ μεα. Θλλθμ αδμοδθμ ει vισ, εαμ vερι qθανδο αδ. Vελ ιλλθδ ετιαμ σιγνιφερθμqθε εα, μοδθσ θτιναμ παρτεμ vιξ εα.

                Ετ δθο σολεατ αθδιαμ, σιτ πθταντ σανcτθσ ιδ. Αν αccθμσαν ιντερπρεταρισ εθμ, μελ νολθισσε διγνισσιμ νε. Φορενσιβθσ ρεφορμιδανσ θλλαμcορπερ θτ ηασ, ναμ απεριαμ αλιqθιδ αν. Cθ σολθμ δελενιτ πατριοqθε εθμ, δετραcτο cονσετετθρ εστ τε. Νοvθμ σανcτθσ σεδ νο.
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black,
                numberOfLines: 0

            ),
            CVLabelConfig(
                text: """
                東沢族応同市総暮見送軟因旧野声。療名岡無会婚必文政職産首堪。原馬果制前興禁出部医保機出。賞響子恵横大厳著美無新殺常芸観載。上属力一本彰料必転指影未税廟赤府研。読煙責負力異寺先発事製量情停並。国圏場権電別新力際営測進必。事藤着人体存止作月玉社英題写予者。間引内一強客透人戦一家万暮読。種扱報崎若陣加府大姿平問写提化針離定。

                足己謙告保士清修根選暮区細理貨聞年半。読治問形球漂注出裏下公療演続。芸意記栄山写日撃掲国主治当性発。生意逃免渡資一取引裕督転。応点続果安罰村必禁家政拳。写禁法考証言心彫埼権川関員奏届新営覚掲。南応要参愛類娘都誰定尚同勝積鎌記写塁。政回過市主覧貨張加主子義空教対券。載捕構方聞度名出結字夜何動問暮理詳半話。
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black,
                numberOfLines: 0
            ),
            CVLabelConfig(
                text: """
                Lorem ipsum dolor sit amet 😟, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem 🧐, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac 🤞 ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black,
                numberOfLines: 0
            ),
            CVLabelConfig(
                text: """
                Lorem ipsum dolor sit amet 😟, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem 🧐, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac 🤞 ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black,
                numberOfLines: 2
            ),
            CVLabelConfig(
                text: """
                Lorem ipsum dolor sit amet 😟, consectetur adipiscing elit. Nullam lectus nulla, eleifend eget libero sit amet, tempor lobortis lacus. Nulla luctus id mi a auctor. Etiam bibendum sed ante et blandit. Phasellus bibendum commodo dapibus. Vivamus lorem diam, finibus vitae mi vel, dignissim ornare felis. Praesent nibh sem 🧐, bibendum vitae fringilla ac, sodales ut ipsum. Vestibulum metus magna, elementum eu dapibus in, faucibus at lacus. In ac 🤞 ornare nisi, ac fringilla sem. Sed ultricies sollicitudin semper. In hac habitasse platea dictumst.
                """,
                font: .ows_dynamicTypeBody,
                textColor: .black,
                numberOfLines: 5,
                lineBreakMode: .byTruncatingMiddle
            )
        ]

        for config in configs {
            for possibleWidth: CGFloat in stride(from: 100, to: 2000, by: 50) {
                let viewSize = CVText.measureLabel(mode: .view, config: config, maxWidth: possibleWidth)
                let defaultSize = CVText.measureLabel(config: config, maxWidth: possibleWidth)
                AssertLessThanUpToLimitOrEqualTo(viewSize.width, defaultSize.width, limit: 5)

                if config.containsCJKCharacters {
                    // TODO: In rare instances, measurement of CJK can be off by a lot, but
                    // always in the "too big" direction, so nothing will clip. We should try
                    // and fix this, but in simple cases it generally seems OK.
                    XCTAssertLessThanOrEqual(viewSize.height, defaultSize.height)
                } else {
                    AssertLessThanUpToLimitOrEqualTo(viewSize.height, defaultSize.height, limit: 2)
                }
            }
        }
    }

    public func AssertLessThanUpToLimitOrEqualTo<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, limit: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T: Comparable & Numeric {
        XCTAssertLessThanOrEqual(try expression1(), try expression2(), message(), file: file, line: line)
        XCTAssertGreaterThanOrEqual(try expression1() + limit, try expression2(), message(), file: file, line: line)
    }
}
