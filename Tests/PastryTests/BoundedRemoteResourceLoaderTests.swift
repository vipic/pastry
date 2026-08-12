import XCTest
@testable import Pastry

final class BoundedRemoteResourceLoaderTests: XCTestCase {
    func testAccumulatorAcceptsChunksUpToLimit() {
        var accumulator = BoundedDataAccumulator(maxBytes: 5)

        XCTAssertTrue(accumulator.append(Data([1, 2])))
        XCTAssertTrue(accumulator.append(Data([3, 4, 5])))
        XCTAssertEqual(accumulator.data, Data([1, 2, 3, 4, 5]))
    }

    func testAccumulatorRejectsChunkBeforeBufferExceedsLimit() {
        var accumulator = BoundedDataAccumulator(maxBytes: 4)

        XCTAssertTrue(accumulator.append(Data([1, 2, 3])))
        XCTAssertFalse(accumulator.append(Data([4, 5])))
        XCTAssertEqual(accumulator.data, Data([1, 2, 3]))
    }
}
