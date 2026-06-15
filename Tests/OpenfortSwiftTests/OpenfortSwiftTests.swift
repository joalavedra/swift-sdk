import Foundation
import Testing
@testable import OpenfortSwift

// MARK: - OFERC20.blockRanges (eth_getLogs chunking)

@Test func blockRangesCoversWholeSpanInChunks() {
    let ranges = OFERC20.blockRanges(latest: 10_000, span: 24_000, chunk: 2_000)
    // span is clamped to `latest` (can't scan before block 0): blocks 0...10_000 inclusive.
    #expect(ranges.first?.to == 10_000)
    #expect(ranges.last?.from == 0)
    // Each chunk holds at most 2000 blocks (inclusive range, so `to - from + 1 <= 2000`).
    #expect(ranges.allSatisfy { $0.to - $0.from + 1 <= 2_000 })
    // Ranges are contiguous and descending with no gaps or overlaps.
    for (newer, older) in zip(ranges, ranges.dropFirst()) {
        #expect(newer.from == older.to + 1)
    }
}

@Test func blockRangesRespectsSpanSmallerThanChunk() {
    let ranges = OFERC20.blockRanges(latest: 5_000, span: 500, chunk: 2_000)
    #expect(ranges.count == 1)
    #expect(ranges[0].to == 5_000)
    #expect(ranges[0].from == 4_501)
}

@Test func blockRangesEmptyForZeroSpan() {
    #expect(OFERC20.blockRanges(latest: 100, span: 0, chunk: 2_000).isEmpty)
}

@Test func blockRangesDoesNotUnderflowPastGenesis() {
    let ranges = OFERC20.blockRanges(latest: 1_500, span: 24_000, chunk: 2_000)
    #expect(ranges.count == 1)
    #expect(ranges[0].from == 0)
    #expect(ranges[0].to == 1_500)
}

// MARK: - Array.chunked

@Test func chunkedSplitsEvenly() {
    #expect([1, 2, 3, 4, 5].chunked(into: 2) == [[1, 2], [3, 4], [5]])
}

@Test func chunkedEmptyArray() {
    #expect([Int]().chunked(into: 3) == [])
}

@Test func chunkedZeroSizeReturnsWhole() {
    #expect([1, 2, 3].chunked(into: 0) == [[1, 2, 3]])
}

// MARK: - OFERC20.baseUnits

@Test func baseUnitsScalesByDecimals() {
    #expect(OFERC20.baseUnits(Decimal(string: "1.5")!, decimals: 6) == "0x16e360")
    #expect(OFERC20.baseUnits(Decimal(1), decimals: 18) == "0xde0b6b3a7640000")
    #expect(OFERC20.baseUnits(Decimal(0), decimals: 6) == "0x0")
}

@Test func baseUnitsTruncatesSubUnitDust() {
    // 1.0000005 USDC (6 decimals) → 1_000_000 base units (the trailing 0.5 unit is dropped).
    #expect(OFERC20.baseUnits(Decimal(string: "1.0000005")!, decimals: 6) == "0xf4240")
}

// MARK: - OFTokenTransfer

@Test func tokenTransferOutgoingFlag() {
    let outgoing = OFTokenTransfer(
        hash: "0xabc", from: "0xowner", to: "0xother", value: "100", blockNumber: 1, isOutgoing: true
    )
    let incoming = OFTokenTransfer(
        hash: "0xdef", from: "0xother", to: "0xowner", value: "200", blockNumber: 2, isOutgoing: false
    )
    #expect(outgoing.isOutgoing)
    #expect(!incoming.isOutgoing)
    #expect(outgoing.value == "100")
}
