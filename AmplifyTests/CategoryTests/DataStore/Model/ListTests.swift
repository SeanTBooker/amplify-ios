//
// Copyright 2018-2021 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import Amplify
import CwlPreconditionTesting

class ListTests: XCTestCase {

    override func setUp() {
        ModelListDecoderRegistry.reset()
    }

    struct BasicModel: Model {
        var id: Identifier
    }

    class MockListDecoder: ModelListDecoder {
        static func shouldDecode(decoder: Decoder) -> Bool {
            guard let json = try? JSONValue(from: decoder) else {
                return false
            }
            if case .array = json {
                return true
            }
            return false
        }

        static func getListProvider<ModelType: Model>(modelType: ModelType.Type,
                                                      decoder: Decoder) throws -> AnyModelListProvider<ModelType> {
            let json = try JSONValue(from: decoder)
            if case .array = json {
                let elements = try [ModelType](from: decoder)
                return MockListProvider<ModelType>(elements: elements).eraseToAnyModelListProvider()
            } else {
                return MockListProvider<ModelType>(elements: []).eraseToAnyModelListProvider()
            }
        }
    }

    class MockListProvider<Element: Model>: ModelListProvider {
        let elements: [Element]
        var error: CoreError?

        public init(elements: [Element], error: CoreError? = nil) {
            self.elements = elements
            self.error = error
        }

        public func load() -> Result<[Element], CoreError> {
            if let error = error {
                return .failure(error)
            } else {
                return .success(elements)
            }
        }

        public func load(completion: (Result<[Element], CoreError>) -> Void) {
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(elements))
            }
        }

        public func hasNextPage() -> Bool {
            false
        }

        public func getNextPage(completion: (Result<List<Element>, CoreError>) -> Void) {
            if let error = error {
                completion(.failure(error))
            } else {
                fatalError("Mock not implemented")
            }
        }
    }

    func testModelListDecoderRegistry() throws {
        XCTAssertEqual(ModelListDecoderRegistry.listDecoders.get().count, 0)
        ModelListDecoderRegistry.registerDecoder(MockListDecoder.self)
        XCTAssertEqual(ModelListDecoderRegistry.listDecoders.get().count, 1)
    }

    func testDecodeWithMockListDecoder() throws {
        ModelListDecoderRegistry.registerDecoder(MockListDecoder.self)
        XCTAssertEqual(ModelListDecoderRegistry.listDecoders.get().count, 1)
        let data: JSONValue = [
            ["id": "1"],
            ["id": "2"]
        ]

        let serializedData = try ListTests.encode(json: data)
        let list = try ListTests.decode(serializedData, responseType: BasicModel.self)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.startIndex, 0)
        XCTAssertEqual(list.endIndex, 2)
        XCTAssertEqual(list.index(after: 1), 2)
        XCTAssertNotNil(list[0])
        let iterateSuccess = expectation(description: "Iterate over the list successfullly")
        iterateSuccess.expectedFulfillmentCount = 2
        list.makeIterator().forEach { _ in
            iterateSuccess.fulfill()
        }
        wait(for: [iterateSuccess], timeout: 1)
        let json = try? ListTests.toJSON(list: list)
        XCTAssertEqual(json, """
            [{\"id\":\"1\"},{\"id\":\"2\"}]
            """)
    }

    func testDecodeToDefaultListWithArrayLiteralListProvider() throws {
        XCTAssertEqual(ModelListDecoderRegistry.listDecoders.get().count, 0)
        let data: JSONValue = [
            ["id": "1"],
            ["id": "2"]
        ]

        let serializedData = try ListTests.encode(json: data)
        let list = try ListTests.decode(serializedData, responseType: BasicModel.self)
        XCTAssertNotNil(list)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.startIndex, 0)
        XCTAssertEqual(list.endIndex, 2)
        XCTAssertEqual(list.index(after: 1), 2)
        XCTAssertNotNil(list[0])
        let iterateSuccess = expectation(description: "Iterate over the list successfullly")
        iterateSuccess.expectedFulfillmentCount = 2
        list.makeIterator().forEach { _ in
            iterateSuccess.fulfill()
        }
        wait(for: [iterateSuccess], timeout: 1)
        XCTAssertFalse(list.listProvider.hasNextPage())
        let getNextPageFail = expectation(description: "getNextPage should fail")
        list.listProvider.getNextPage { result in
            switch result {
            case .success:
                XCTFail("Should not be successfully")
            case .failure:
                getNextPageFail.fulfill()
            }
        }
        wait(for: [getNextPageFail], timeout: 1)
    }

    func testDecodeToDefaultListWithArrayLiteralListProviderFromInvalidJSON() throws {
        XCTAssertEqual(ModelListDecoderRegistry.listDecoders.get().count, 0)
        let data: JSONValue = "NotArray"
        let serializedData = try ListTests.encode(json: data)
        let list = try ListTests.decode(serializedData, responseType: BasicModel.self)
        XCTAssertNotNil(list)
        XCTAssertEqual(list.count, 0)
    }

    func testListLoadWithDataStoreCompletion() throws {
        XCTAssertEqual(ModelListDecoderRegistry.listDecoders.get().count, 0)
        let data: JSONValue = [
            ["id": "1"],
            ["id": "2"]
        ]

        let serializedData = try ListTests.encode(json: data)
        let list = try ListTests.decode(serializedData, responseType: BasicModel.self)
        let loadComplete = expectation(description: "Load completed")
        list.load { result in
            switch result {
            case .success(let elements):
                XCTAssertEqual(elements.count, 2)
                loadComplete.fulfill()
            case .failure(let dataStoreError):
                XCTFail("\(dataStoreError)")
            }
        }
        wait(for: [loadComplete], timeout: 1)
    }

    func testListLoadWithDataStoreError() {
        let mockListProvider = MockListProvider<BasicModel>(
            elements: [BasicModel](),
            error: .pluginError(DataStoreError.internalOperation("", "", nil))).eraseToAnyModelListProvider()
        let list = List(loadProvider: mockListProvider)
        let loadComplete = expectation(description: "Load completed")
        list.load { result in
            switch result {
            case .failure(let error):
                guard case .internalOperation = error else {
                    XCTFail("error should be DataStore Error")
                    return
                }
                loadComplete.fulfill()
            case .success:
                XCTFail("Should have failed")
            }
        }
        wait(for: [loadComplete], timeout: 1)
    }

    func testListLoadWithListOperationError() {
        let mockListProvider = MockListProvider<BasicModel>(
            elements: [BasicModel](),
            error: .listOperation("", "", nil)).eraseToAnyModelListProvider()
        let list = List(loadProvider: mockListProvider)
        let loadComplete = expectation(description: "Load completed")
        list.load { result in
            switch result {
            case .failure(let error):
                guard case .invalidOperation = error else {
                    XCTFail("error should be DataStoreError.invalidOperation")
                    return
                }
                loadComplete.fulfill()
            case .success:
                XCTFail("Should have failed")
            }
        }
        wait(for: [loadComplete], timeout: 1)
    }

    func testListLoadWithClientValidationError() {
        let mockListProvider = MockListProvider<BasicModel>(
            elements: [BasicModel](),
            error: .clientValidation("", "", nil)).eraseToAnyModelListProvider()
        let list = List(loadProvider: mockListProvider)
        let loadComplete = expectation(description: "Load completed")
        list.load { result in
            switch result {
            case .failure(let error):
                guard case .invalidOperation = error else {
                    XCTFail("error should be DataStoreError.invalidOperation")
                    return
                }
                loadComplete.fulfill()
            case .success:
                XCTFail("Should have failed")
            }
        }
        wait(for: [loadComplete], timeout: 1)
    }

    func testListLoadWithUnknownError() {
        let mockListProvider = MockListProvider<BasicModel>(
            elements: [BasicModel](),
            error: .unknown("")).eraseToAnyModelListProvider()
        let list = List(loadProvider: mockListProvider)
        let loadComplete = expectation(description: "Load completed")
        list.load { result in
            switch result {
            case .failure(let error):
                guard case .invalidOperation = error else {
                    XCTFail("error should be DataStoreError.invalidOperation")
                    return
                }
                loadComplete.fulfill()
            case .success:
                XCTFail("Should have failed")
            }
        }
        wait(for: [loadComplete], timeout: 1)
    }

    func testListFailedImplicitLoadDoesNotChangeLoadedState() {
        let mockListProvider = MockListProvider<BasicModel>(
            elements: [BasicModel](),
            error: .pluginError(DataStoreError.internalOperation("", "", nil)))
            .eraseToAnyModelListProvider()
        let list = List(loadProvider: mockListProvider)
        guard case .notLoaded = list.loadedState else {
            XCTFail("Should not be loaded")
            return
        }
        XCTAssertEqual(list.elements.count, 0)
        guard case .notLoaded = list.loadedState else {
            XCTFail("Should not be loaded")
            return
        }
    }

    func testSynchronousLoadFailWithAssert() {
        let mockListProvider = MockListProvider<BasicModel>(
            elements: [BasicModel](),
            error: .unknown("")).eraseToAnyModelListProvider()
        let list = List(loadProvider: mockListProvider)
        let caughtAssert = catchBadInstruction {
            list.load()
        }
        XCTAssertNotNil(caughtAssert)
    }

    func testDecodeAndEncodeEmptyArray() throws {
        XCTAssertEqual(ModelListDecoderRegistry.listDecoders.get().count, 0)
        let data: JSONValue = []
        let serializedData = try ListTests.encode(json: data)
        let list = try ListTests.decode(serializedData, responseType: BasicModel.self)
        XCTAssertNotNil(list)
        XCTAssertEqual(list.count, 0)
        let json = try? ListTests.toJSON(list: list)
        XCTAssertEqual(json, "[]")
    }

    // MARK: - Helpers

    private static func encode(json: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = ModelDateFormatting.encodingStrategy
        return try encoder.encode(json)
    }

    private static func toJSON<ModelType: Model>(list: List<ModelType>) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = ModelDateFormatting.encodingStrategy
        let data = try encoder.encode(list)
        guard let json = String(data: data, encoding: .utf8) else {
            XCTFail("Could not get JSON string from data")
            return ""
        }
        return json
    }

    private static func decode<R: Decodable>(_ data: Data, responseType: R.Type) throws -> List<R> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = ModelDateFormatting.decodingStrategy
        return try decoder.decode(List<R>.self, from: data)
    }
}