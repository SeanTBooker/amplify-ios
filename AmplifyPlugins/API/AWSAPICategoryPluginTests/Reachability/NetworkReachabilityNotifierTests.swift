//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import XCTest
import Reachability
import Combine
@testable import AWSAPICategoryPlugin

@available(iOS 13.0, *)
class NetworkReachabilityNotifierTests: XCTestCase {
    var notification: Notification!
    var notifier: NetworkReachabilityNotifier!

    override func setUp() {
        do {
            notifier = try NetworkReachabilityNotifier(
                host: "localhost",
                allowsCellularAccess: true,
                reachabilityFactory: MockNetworkReachabilityProvidingFactory.self
            )
        } catch {
            XCTFail("failed to init NetworkReachabilityNotifier")
        }
        MockReachability.iConnection = .wifi
    }

    func testWifiConnectivity() {
        MockReachability.iConnection = .wifi
        let expect = expectation(description: ".sink receives values")
        var values = [Bool]()
        let cancellable = notifier.publisher.sink(receiveCompletion: { _ in
            XCTFail("Not expecting any error")
        }, receiveValue: { value in
            values.append(value.isOnline)
            if values.count == 2 {
                XCTAssertFalse(values[0])
                XCTAssertTrue(values[1])
                expect.fulfill()
            }
        })
        notification = Notification.init(name: .reachabilityChanged)
        NotificationCenter.default.post(notification)

        waitForExpectations(timeout: 1.0)
        cancellable.cancel()
    }

    func testCellularConnectivity() {
        MockReachability.iConnection = .wifi
        let expect = expectation(description: ".sink receives values")
        let cancellable = notifier.publisher.sink(receiveCompletion: { _ in
            XCTFail("Not expecting any error")
        }, receiveValue: { value in
            XCTAssertTrue(value.isOnline)
            expect.fulfill()
        })

        notification = Notification.init(name: .reachabilityChanged)
        NotificationCenter.default.post(notification)

        waitForExpectations(timeout: 1.0)
        cancellable.cancel()
    }

    func testNoConnectivity() {
        MockReachability.iConnection = .unavailable
        let expect = expectation(description: ".sink receives values")
        var values = [Bool]()
        let cancellable = notifier.publisher.sink(receiveCompletion: { _ in
            XCTFail("Not expecting any error")
        }, receiveValue: { value in
            values.append(value.isOnline)
            if values.count == 2 {
                XCTAssertTrue(values[0])
                XCTAssertFalse(values[1])
                expect.fulfill()
            }
        })

        notification = Notification.init(name: .reachabilityChanged)
        NotificationCenter.default.post(notification)

        waitForExpectations(timeout: 1.0)
        cancellable.cancel()
    }

    func testWifiConnectivity_publisherGoesOutOfScope() {
        MockReachability.iConnection = .wifi
        let initialValueExpect = expectation(description: ".sink receives default value")
        let completeExpect = expectation(description: ".sink receives completion")
        let cancellable = notifier.publisher.sink(receiveCompletion: { _ in
            completeExpect.fulfill()
        }, receiveValue: { value in
            XCTAssertTrue(value.isOnline)
            initialValueExpect.fulfill()
        })

        wait(for: [initialValueExpect], timeout: 1.0)
        notifier = nil
        notification = Notification.init(name: .reachabilityChanged)
        NotificationCenter.default.post(notification)

        wait(for: [completeExpect], timeout: 1.0)
        cancellable.cancel()
    }
}
