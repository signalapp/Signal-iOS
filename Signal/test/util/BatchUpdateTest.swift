//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit
@testable import Signal
@testable import SignalMessaging

class BatchUpdateTest: SignalBaseTest {
    func testScenario1() {
        let oldValueIdList = [
            "ggbb3dk2uJONs9yDvWUj+SFV5b5ITNlJRhzsAd03Lmts=",
            "gKfuzZJ2Q5CvLhhiwlJDP4gIPTcJIPVpJJUoHmrYFWBs=",
            "gbQLkYNg7HBWQTBSFxdHdo5vMtmtDcgkDDewCIGtlFus=",
            "g9a8EEJbSS9ycXuZSZp/W0EW52qgis8RVJbCFeVTWxv4=",
            "gvo4u6qFDEP4LhPpBjgvdQNWFSHkN18+bdhrFv8yNI/E=",
            "g7WFr/Nh+ZGy4V+US8J0pQONioDk2EW/R8SIilLKNYek=",
            "g+mOkpBQ+2f5uNcXQBS7aAjvefHioLzi+Eeue05BfNmo=",
            "gRakefjunoLIqQEiCDUvJyjtxrBeHsvX5YMd8O4yaG1I=",
            "glNBupGj/brC04rL1RQpMwu7Afnw204rVqi6yXd6rkRU=",
            "gcLOWngOjWEWjddHR7NNAQ+hTwL+MVxreFGaYViKIP7M=",
            "g4De4errdgdozX70sd4pxakD2PDRtqrjJVFmVfSz4GtI=",
            "g2ZqVMAQ/y0XP0iw9mlxeGdkjdB3uItQ+vwA+VvVVvdI=",
            "gdsV1Lss8Q+wNX2Ig6J0O+p3Z7gP9V3V9pNTRtyH4PFQ=",
            "gpYS+mI417KNfG66YE4QzkWmPNpR2MkDnqxzzO6oKKBg=",
            "gTNUijTV0EO625DsATyvRHbJCdsFDdCOSzAVb63ek1Ws=",
            "gT04CsPREDl1JIVmiEKCiiVlTK2jxDsfijCi8GhufZRQ=",
            "BF5E8DF8-7B4F-4CF3-BCA0-849310B8A2AF",
            "g/mYISM1hTIYelZay1cp69Pjes2mUxZfPijZn35WbAW8=",
            "6B7DE12A-42E9-4107-8B85-E517044FC916",
            "6CC9B707-3E4C-4AB5-AEF0-E2204B5EAEE1",
            "gHo91m8MnNTSF2RvUopuDWEqpIYXPYbT5Yl1YsJV/4Hc=",
            "gwEeJdwl8QuaRr36artIFMDzlqVqQo7rKI2urJfiLWu0=",
            "gLzu5oB+phTDa44aZINZ8aOGSW/DFNtXc87YkUrMDijw=",
            "gviTNOTyuwGy4bN+CLO1wQfLtM5m1PUdrYwDtXT6W5jk=",
            "gLCLWLb+36RqMu6sPRhqVVuQJiqCoQOw/F2yK2jx0sHM=",
            "gY5zWwCuDtEMPV7Z2qN2nxBNnubxjFUqPWa7fx9NXWyE=",
            "E8E71C36-2494-4377-A612-34F4CF72DEE2",
            "gN957pZaRxYByl+wAGyJUZwF1n1tuoSaA17OolFIrDXk=",
            "DFE42350-B3C2-4204-862E-FB01007437AF",
            "guo1oncirWtfJuBhExLE4e9GpR/rlhlCr4O4lN8WW3DY=",
            "gNJAnJp8wc7pfNVf9tYUfoUbCjFSWtoOUbhSxqqib+aM=",
            "gHTNzDWL4Qgv21/98X3iKXk56LIOVGJQ6/nPfqJYcJKg=",
            "gxqnwX2abHLYlG9ndglczOb0g40geAx24yz1OqUt7w1M=",
            "gkg/nJXDM3yptgqWvkLCTNzzoAzMFJLoNe43axSVLMeY=",
            "gHWI9ZKdYp6xPmo5cLZXrn7b/GIjF7yWycRcLoz3wg+Y=",
            "gGGxsuC12I1TCw0lDvnsa1u0Uu0Uz+wRdJ958dRKO55o=",
            "275A76F8-6877-42FE-BBA9-677319343235",
            "2A05A2CB-666A-471F-8414-2BFB8C1600D4",
            "gE0EvQmyd2SkMXSudXUxTw+XBBd20QjKGk3qKnhAKWMg=",
            "g+W3gBq93pI6d02P9BfAdMmLpGjYiLOxvzejP4aifQuY=",
            "gMWim99rBgWhQ7ffNTO8PJdKVeN0uxLbVz6dZX6dLbIQ=",
            "gMFQDkj7krcDtRNiMXdWI4CxnuZr/Pq4NmN+0d9voraQ=",
            "gzxTBn/IYCHrudmyqVcbt1/OwlXC+BCEd15ql1mr+E28=",
            "gv1Xmtc1hr+NIujIv/FgD7toU/0SYvUUXd37dBKIKTLA=",
            "gGv1k9uKKJCHjca5E3ar28EqOWPyqN1zpebNAkSsRojU=",
            "gGb/fXSaJ4AZyUDaUiJGm5YTwDecyr//Qxs9q+LaPCUQ=",
            "g3U9dcUsPRUcTQXKxY4VrMXu/9mnNX0FDx46ZO43sits=",
            "gJAScm9GEHP872awsDqN/7kyMiykGwW0Y+/FRa8SiMns=",
            "g6EJU1AHHZRlA76lIGeiJ8CEAHlLkgaBpYczFSQByBeI=",
            "gebS8VgJha+wdNV4qne01bZKHtnextGf8nQuYcTYiieg=",
            "gajFDWIMRZsi2Gqw2ROKPQd42x5x9r1SH5BU2RPV5quw=",
            "gwi90aJPqikdlzqizxThKJ30+xk7XMOWxa55o7InrfWY=",
            "g3uwDuyOOvAfoEr79Sc437FAQtBtRB47p0o8e9TEf1Gs=",
            "gti7xZMVDT7/Omdhr5ZUcbImsWjQpBsn9oFwhQaa1bvE=",
            "gMAPHk6f1r16qg+stsvU4o4u3y5QlHFR90JKRlDufhB4=",
            "gxlInCvpkZd46uFqwlkVXQWj1Rghv9N52oVIELaEmAc4=",
            "639AA9D7-F382-405C-9DC0-43CE2FD6DABD",
            "gtJ2LR99a0rtEVNRBQrt4s8hiBTBVhgi+FLBQSKKVUYU=",
            "gT61ND5TWAi+dJOJJrEBPXN1OWhIZLQVdQDxyvIgz88c=",
            "gWMTaHAu9hmHKZOnZG+z1UmgP1j18zfpJeIWtBb0PlrM=",
            "06E82152-E19D-4B90-A9F6-D7F333CB7170",
            "EE82CAA5-70B6-43DF-BFD7-E6188C5C2B23",
            "g6o/qq0MnXk+5FvxAq7wFRQiq08holjaH57LMKfaO8P8=",
            "ghSeWGUZK924DgQKKRkh0mbDfgA9YW3PUVtF3M0WFa7w=",
            "g/bhQLKkIXYdOE4/yY57rMCnG0dmENpWGgTrVD5O/TPw=",
            "gyqLPh6Fvm9nyChzlQmG+xkf42Hvl13h2736LTUNf5hI=",
            "gRAHscZ8yNwTVXl7CJrZaASjLsmUDqL1eDhfaO9zUyFU="
        ]
        let newValueIdList = [
            "glNBupGj/brC04rL1RQpMwu7Afnw204rVqi6yXd6rkRU=",
            "ggbb3dk2uJONs9yDvWUj+SFV5b5ITNlJRhzsAd03Lmts=",
            "gKfuzZJ2Q5CvLhhiwlJDP4gIPTcJIPVpJJUoHmrYFWBs=",
            "gbQLkYNg7HBWQTBSFxdHdo5vMtmtDcgkDDewCIGtlFus=",
            "g9a8EEJbSS9ycXuZSZp/W0EW52qgis8RVJbCFeVTWxv4=",
            "gvo4u6qFDEP4LhPpBjgvdQNWFSHkN18+bdhrFv8yNI/E=",
            "g7WFr/Nh+ZGy4V+US8J0pQONioDk2EW/R8SIilLKNYek=",
            "g+mOkpBQ+2f5uNcXQBS7aAjvefHioLzi+Eeue05BfNmo=",
            "gRakefjunoLIqQEiCDUvJyjtxrBeHsvX5YMd8O4yaG1I=",
            "gcLOWngOjWEWjddHR7NNAQ+hTwL+MVxreFGaYViKIP7M=",
            "g4De4errdgdozX70sd4pxakD2PDRtqrjJVFmVfSz4GtI=",
            "g2ZqVMAQ/y0XP0iw9mlxeGdkjdB3uItQ+vwA+VvVVvdI=",
            "gdsV1Lss8Q+wNX2Ig6J0O+p3Z7gP9V3V9pNTRtyH4PFQ=",
            "gpYS+mI417KNfG66YE4QzkWmPNpR2MkDnqxzzO6oKKBg=",
            "gTNUijTV0EO625DsATyvRHbJCdsFDdCOSzAVb63ek1Ws=",
            "gT04CsPREDl1JIVmiEKCiiVlTK2jxDsfijCi8GhufZRQ=",
            "BF5E8DF8-7B4F-4CF3-BCA0-849310B8A2AF",
            "g/mYISM1hTIYelZay1cp69Pjes2mUxZfPijZn35WbAW8=",
            "6B7DE12A-42E9-4107-8B85-E517044FC916",
            "6CC9B707-3E4C-4AB5-AEF0-E2204B5EAEE1",
            "gHo91m8MnNTSF2RvUopuDWEqpIYXPYbT5Yl1YsJV/4Hc=",
            "gwEeJdwl8QuaRr36artIFMDzlqVqQo7rKI2urJfiLWu0=",
            "gLzu5oB+phTDa44aZINZ8aOGSW/DFNtXc87YkUrMDijw=",
            "gviTNOTyuwGy4bN+CLO1wQfLtM5m1PUdrYwDtXT6W5jk=",
            "gLCLWLb+36RqMu6sPRhqVVuQJiqCoQOw/F2yK2jx0sHM=",
            "gY5zWwCuDtEMPV7Z2qN2nxBNnubxjFUqPWa7fx9NXWyE=",
            "E8E71C36-2494-4377-A612-34F4CF72DEE2",
            "gN957pZaRxYByl+wAGyJUZwF1n1tuoSaA17OolFIrDXk=",
            "DFE42350-B3C2-4204-862E-FB01007437AF",
            "guo1oncirWtfJuBhExLE4e9GpR/rlhlCr4O4lN8WW3DY=",
            "gNJAnJp8wc7pfNVf9tYUfoUbCjFSWtoOUbhSxqqib+aM=",
            "gHTNzDWL4Qgv21/98X3iKXk56LIOVGJQ6/nPfqJYcJKg=",
            "gxqnwX2abHLYlG9ndglczOb0g40geAx24yz1OqUt7w1M=",
            "gkg/nJXDM3yptgqWvkLCTNzzoAzMFJLoNe43axSVLMeY=",
            "gHWI9ZKdYp6xPmo5cLZXrn7b/GIjF7yWycRcLoz3wg+Y=",
            "gGGxsuC12I1TCw0lDvnsa1u0Uu0Uz+wRdJ958dRKO55o=",
            "275A76F8-6877-42FE-BBA9-677319343235",
            "2A05A2CB-666A-471F-8414-2BFB8C1600D4",
            "gE0EvQmyd2SkMXSudXUxTw+XBBd20QjKGk3qKnhAKWMg=",
            "g+W3gBq93pI6d02P9BfAdMmLpGjYiLOxvzejP4aifQuY=",
            "gMWim99rBgWhQ7ffNTO8PJdKVeN0uxLbVz6dZX6dLbIQ=",
            "gMFQDkj7krcDtRNiMXdWI4CxnuZr/Pq4NmN+0d9voraQ=",
            "gzxTBn/IYCHrudmyqVcbt1/OwlXC+BCEd15ql1mr+E28=",
            "gv1Xmtc1hr+NIujIv/FgD7toU/0SYvUUXd37dBKIKTLA=",
            "gGv1k9uKKJCHjca5E3ar28EqOWPyqN1zpebNAkSsRojU=",
            "gGb/fXSaJ4AZyUDaUiJGm5YTwDecyr//Qxs9q+LaPCUQ=",
            "g3U9dcUsPRUcTQXKxY4VrMXu/9mnNX0FDx46ZO43sits=",
            "gJAScm9GEHP872awsDqN/7kyMiykGwW0Y+/FRa8SiMns=",
            "g6EJU1AHHZRlA76lIGeiJ8CEAHlLkgaBpYczFSQByBeI=",
            "gebS8VgJha+wdNV4qne01bZKHtnextGf8nQuYcTYiieg=",
            "gajFDWIMRZsi2Gqw2ROKPQd42x5x9r1SH5BU2RPV5quw=",
            "gwi90aJPqikdlzqizxThKJ30+xk7XMOWxa55o7InrfWY=",
            "g3uwDuyOOvAfoEr79Sc437FAQtBtRB47p0o8e9TEf1Gs=",
            "gti7xZMVDT7/Omdhr5ZUcbImsWjQpBsn9oFwhQaa1bvE=",
            "gMAPHk6f1r16qg+stsvU4o4u3y5QlHFR90JKRlDufhB4=",
            "gxlInCvpkZd46uFqwlkVXQWj1Rghv9N52oVIELaEmAc4=",
            "639AA9D7-F382-405C-9DC0-43CE2FD6DABD",
            "gtJ2LR99a0rtEVNRBQrt4s8hiBTBVhgi+FLBQSKKVUYU=",
            "gT61ND5TWAi+dJOJJrEBPXN1OWhIZLQVdQDxyvIgz88c=",
            "gWMTaHAu9hmHKZOnZG+z1UmgP1j18zfpJeIWtBb0PlrM=",
            "06E82152-E19D-4B90-A9F6-D7F333CB7170",
            "EE82CAA5-70B6-43DF-BFD7-E6188C5C2B23",
            "g6o/qq0MnXk+5FvxAq7wFRQiq08holjaH57LMKfaO8P8=",
            "ghSeWGUZK924DgQKKRkh0mbDfgA9YW3PUVtF3M0WFa7w=",
            "g/bhQLKkIXYdOE4/yY57rMCnG0dmENpWGgTrVD5O/TPw=",
            "gyqLPh6Fvm9nyChzlQmG+xkf42Hvl13h2736LTUNf5hI=",
            "gRAHscZ8yNwTVXl7CJrZaASjLsmUDqL1eDhfaO9zUyFU="
        ]

        let oldValues = oldValueIdList.map { MockValue($0) }
        let newValues = newValueIdList.map { MockValue($0) }

        let batchUpdateItems = try! BatchUpdate.build(viewType: .uiTableView,
                                                      oldValues: oldValues,
                                                      newValues: newValues,
                                                      changedValues: [])
        XCTAssertTrue(!batchUpdateItems.isEmpty)
    }

    func testScenario2() {
        let oldValueIdList = [
            "A",
            "B",
            "C",
            "D",
            "E",
            "F"
        ]
        let newValueIdList = [
            "B",
            "C",
            "D",
            "E",
            "F",

            // The first element becomes last.
            "A"
        ]

        let oldValues = oldValueIdList.map { MockValue($0) }
        let newValues = newValueIdList.map { MockValue($0) }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiTableView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [])
            // A UITableView can move one _unchanged_ item with one .move.
            XCTAssertEqual(batchUpdateItems.count, 1)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 0)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 0)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 1)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
        }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiTableView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [ MockValue("A") ])
            // A UITableView can move one _changed_ item with one .move.
            XCTAssertEqual(batchUpdateItems.count, 1)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 0)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 0)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 1)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
        }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiCollectionView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [])
            if BatchUpdate<MockValue>.canUseMoveInCollectionView {
                // A UICollectionView can move one _unchanged_ item with one .move.
                XCTAssertEqual(batchUpdateItems.count, 1)
                XCTAssertEqual(batchUpdateItems.insertItems.count, 0)
                XCTAssertEqual(batchUpdateItems.deleteItems.count, 0)
                XCTAssertEqual(batchUpdateItems.moveItems.count, 1)
                XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
            } else {
                XCTAssertEqual(batchUpdateItems.count, 2)
                XCTAssertEqual(batchUpdateItems.insertItems.count, 1)
                XCTAssertEqual(batchUpdateItems.deleteItems.count, 1)
                XCTAssertEqual(batchUpdateItems.moveItems.count, 0)
                XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
            }
        }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiCollectionView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [ MockValue("A") ])
            // A UICollectionView can move one _changed_ item with
            // one .delete and one .move.
            XCTAssertEqual(batchUpdateItems.count, 2)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 1)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 1)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 0)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
        }
    }

    func testScenario3() {
        let oldValueIdList = [
            "A",
            "B",
            "C",
            "D",
            "E",
            "F"
        ]
        let newValueIdList = [
            // The last element becomes first.
            "F",

            "A",
            "B",
            "C",
            "D",
            "E"
        ]

        let oldValues = oldValueIdList.map { MockValue($0) }
        let newValues = newValueIdList.map { MockValue($0) }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiTableView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [])
            // A UITableView can move one _unchanged_ item with one .move.
            XCTAssertEqual(batchUpdateItems.count, 1)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 0)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 0)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 1)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
        }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiTableView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [ MockValue("F") ])
            // A UITableView can move one _changed_ item with one .move.
            XCTAssertEqual(batchUpdateItems.count, 1)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 0)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 0)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 1)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
        }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiCollectionView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [])
            if BatchUpdate<MockValue>.canUseMoveInCollectionView {
                // A UICollectionView can move one _unchanged_ item with one .move.
                XCTAssertEqual(batchUpdateItems.count, 1)
                XCTAssertEqual(batchUpdateItems.deleteItems.count, 0)
                XCTAssertEqual(batchUpdateItems.insertItems.count, 0)
                XCTAssertEqual(batchUpdateItems.moveItems.count, 1)
                XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
            } else {
                XCTAssertEqual(batchUpdateItems.count, 2)
                XCTAssertEqual(batchUpdateItems.deleteItems.count, 1)
                XCTAssertEqual(batchUpdateItems.insertItems.count, 1)
                XCTAssertEqual(batchUpdateItems.moveItems.count, 0)
                XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
            }
        }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiCollectionView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [ MockValue("F") ])
            // A UICollectionView can move one _changed_ item with
            // one .delete and one .insert.
            XCTAssertEqual(batchUpdateItems.count, 2)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 1)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 1)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 0)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
        }
    }

    func testScenario4() {
        let oldValueIdList = [
            "A",
            "B",
            "C",
            "D",
            "E",
            "F"
        ]
        let newValueIdList = [
            // The last element becomes first.
            "F",

            "B",
            "C",
            "D",
            "E",

            // The first element becomes last.
            "A"
        ]

        let oldValues = oldValueIdList.map { MockValue($0) }
        let newValues = newValueIdList.map { MockValue($0) }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiTableView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [])
            // A UITableView can move two _unchanged_ items with two .moves.
            XCTAssertEqual(batchUpdateItems.count, 2)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 0)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 0)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 2)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
        }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiTableView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [ MockValue("A"), MockValue("F") ])
            // A UITableView can move two _changed_ items with two .moves.
            XCTAssertEqual(batchUpdateItems.count, 2)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 0)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 0)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 2)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
        }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiCollectionView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [])
            if BatchUpdate<MockValue>.canUseMoveInCollectionView {
                // A UICollectionView can move two _unchanged_ items with two .moves.
                XCTAssertEqual(batchUpdateItems.count, 2)
                XCTAssertEqual(batchUpdateItems.deleteItems.count, 0)
                XCTAssertEqual(batchUpdateItems.insertItems.count, 0)
                XCTAssertEqual(batchUpdateItems.moveItems.count, 2)
                XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
            } else {
                XCTAssertEqual(batchUpdateItems.count, 4)
                XCTAssertEqual(batchUpdateItems.deleteItems.count, 2)
                XCTAssertEqual(batchUpdateItems.insertItems.count, 2)
                XCTAssertEqual(batchUpdateItems.moveItems.count, 0)
                XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
            }
        }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiCollectionView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [ MockValue("A"), MockValue("F") ])
            // A UICollectionView can move two _changed_ items with
            // two .deletes and two .inserts.
            XCTAssertEqual(batchUpdateItems.count, 4)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 2)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 2)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 0)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 0)
        }
    }

    func testScenario5() {
        let oldValueIdList = [
            "A",
            "B",
            "C",
            "D",
            "E",
            "F",
            "G",
            "H",
            "I",
            "J",
            "K"
        ]
        // Three items move.
        let newValueIdList = [
            "A",
            // This value moves way up.
            "J",
            "B",
            "D",
            // This value swaps places with an adjacent neighbor.
            "F",
            // This value swaps places with an adjacent neighbor.
            "E",
            "G",
            "H",
            // This value moves way down.
            "C",
            "I",
            "K"
        ]

        let oldValues = oldValueIdList.map { MockValue($0) }
        let newValues = newValueIdList.map { MockValue($0) }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiTableView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [
                                                            // Three items change, one of which moves.
                                                            MockValue("A"),
                                                            MockValue("B"),
                                                            MockValue("C")
                                                          ])
            XCTAssertEqual(batchUpdateItems.count, 5)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 0)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 0)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 3)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 2)
        }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiCollectionView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [
                                                            // Three items change, one of which moves.
                                                            MockValue("A"),
                                                            MockValue("B"),
                                                            MockValue("C")
                                                          ])
            if BatchUpdate<MockValue>.canUseMoveInCollectionView {
                XCTAssertEqual(batchUpdateItems.count, 6)
                XCTAssertEqual(batchUpdateItems.deleteItems.count, 1)
                XCTAssertEqual(batchUpdateItems.insertItems.count, 1)
                XCTAssertEqual(batchUpdateItems.moveItems.count, 2)
                XCTAssertEqual(batchUpdateItems.updateItems.count, 2)
            } else {
                XCTAssertEqual(batchUpdateItems.count, 8)
                XCTAssertEqual(batchUpdateItems.deleteItems.count, 3)
                XCTAssertEqual(batchUpdateItems.insertItems.count, 3)
                XCTAssertEqual(batchUpdateItems.moveItems.count, 0)
                XCTAssertEqual(batchUpdateItems.updateItems.count, 2)
            }
        }
    }

    func testScenario6() {
        let oldValueIdList = [
            "A",
            "B",
            "C",
            "D",
            "E",
            "F",
            "G"
        ]
        // The ordering is reversed.
        let newValueIdList = [
            "G",
            "F",
            "E",
            "D",
            "C",
            "B",
            "A"
        ]

        let oldValues = oldValueIdList.map { MockValue($0) }
        let newValues = newValueIdList.map { MockValue($0) }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiTableView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [
                                                            // All items change.
                                                            MockValue("A"),
                                                            MockValue("B"),
                                                            MockValue("C"),
                                                            MockValue("D"),
                                                            MockValue("E"),
                                                            MockValue("F"),
                                                            MockValue("G")
                                                          ])
            XCTAssertEqual(batchUpdateItems.count, 7)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 0)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 0)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 6)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 1)
        }

        do {
            let batchUpdateItems = try! BatchUpdate.build(viewType: .uiCollectionView,
                                                          oldValues: oldValues,
                                                          newValues: newValues,
                                                          changedValues: [
                                                            // All items change.
                                                            MockValue("A"),
                                                            MockValue("B"),
                                                            MockValue("C"),
                                                            MockValue("D"),
                                                            MockValue("E"),
                                                            MockValue("F"),
                                                            MockValue("G")
                                                          ])
            XCTAssertEqual(batchUpdateItems.count, 13)
            XCTAssertEqual(batchUpdateItems.deleteItems.count, 6)
            XCTAssertEqual(batchUpdateItems.insertItems.count, 6)
            XCTAssertEqual(batchUpdateItems.moveItems.count, 0)
            XCTAssertEqual(batchUpdateItems.updateItems.count, 1)
        }
    }

    typealias MockValue = BatchUpdateMockValue
}

// MARK: -

struct BatchUpdateMockValue: BatchUpdateValue {
    let itemId: String

    init(_ itemId: String) {
        self.itemId = itemId
    }

    var batchUpdateId: String { itemId }
    var logSafeDescription: String { itemId }
}

// MARK: -

extension BatchUpdateType {
    var isDelete: Bool {
        guard case .delete = self else {
            return false
        }
        return true
    }

    var isInsert: Bool {
        guard case .insert = self else {
            return false
        }
        return true
    }

    var isMove: Bool {
        guard case .move = self else {
            return false
        }
        return true
    }

    var isUpdate: Bool {
        guard case .update = self else {
            return false
        }
        return true
    }
}

// MARK: -

typealias BatchUpdateMockItem = BatchUpdate<BatchUpdateMockValue>.Item

extension BatchUpdateMockItem {
    var isDelete: Bool { updateType.isDelete }
    var isInsert: Bool { updateType.isInsert }
    var isMove: Bool { updateType.isMove }
    var isUpdate: Bool { updateType.isUpdate }
}

// MARK: -

extension Array where Element == BatchUpdateMockItem {
    var deleteItems: [BatchUpdateMockItem] { self.filter { $0.isDelete} }
    var insertItems: [BatchUpdateMockItem] { self.filter { $0.isInsert} }
    var moveItems: [BatchUpdateMockItem] { self.filter { $0.isMove} }
    var updateItems: [BatchUpdateMockItem] { self.filter { $0.isUpdate} }
}
