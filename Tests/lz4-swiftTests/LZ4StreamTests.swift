
import XCTest
@testable import lz4_swift
#if canImport(Darwin)
import Darwin
#endif

final class LZ4StreamTests: XCTestCase {
    
    func testStreamingSimple() {
        // Block 1: "Hello World "
        // Block 2: "Hello World " (Should refer to Block 1)
        
        // Setup Compressor
        let cStream = LZ4Stream()
        
        let b1Text = "Hello World Hello World "
        let b1Src = Array(b1Text.utf8)
        var b1Dst = [UInt8](repeating: 0, count: 128)
        
        // Compress Block 1
        let cSize1 = LZ4Compress.compress_fast_continue(cStream, src: b1Src, dst: &b1Dst)
        XCTAssertGreaterThan(cSize1, 0)
        
        // Setup Decompressor
        let dStream = LZ4StreamDecode()
        var b1Decomp = [UInt8](repeating: 0, count: b1Src.count)
        
        // Decompress Block 1
        let dSize1 = LZ4Decompress.decompress_safe_continue(dStream, src: Array(b1Dst[0..<cSize1]), dst: &b1Decomp)
        XCTAssertEqual(dSize1, b1Src.count)
        XCTAssertEqual(b1Decomp, b1Src)
        
        // Update Decompressor Dict
        dStream.setDict(b1Decomp)
        
        // Block 2
        let b2Text = "Hello World Hello World "
        let b2Src = Array(b2Text.utf8)
        var b2Dst = [UInt8](repeating: 0, count: 128)
        
        // Compress Block 2
        let cSize2 = LZ4Compress.compress_fast_continue(cStream, src: b2Src, dst: &b2Dst)
        print("Block 1 Size: \(cSize1). Block 2 Size: \(cSize2)")
        
        // Block 2 should be smaller because it matches Block 1 entirely?
        // Wait, "Hello World Hello World " is 24 bytes.
        // Block 1 will be compressed (Token + Literal + Match).
        // Block 2: Should find match at start of Block 1.
        // So Block 2 should be [Token: Lit=0, MatchLen=24].
        // Match Offset?
        // Distance is 24 bytes.
        // It should match.
        // cSize2 should be very small (Token + Offset). 3 bytes?
        XCTAssertLessThan(cSize2, cSize1)
        
        // Decompress Block 2
        var b2Decomp = [UInt8](repeating: 0, count: b2Src.count)
        let dSize2 = LZ4Decompress.decompress_safe_continue(dStream, src: Array(b2Dst[0..<cSize2]), dst: &b2Decomp)
        
        XCTAssertEqual(dSize2, b2Src.count)
        XCTAssertEqual(b2Decomp, b2Src)
    }
    
    func testStreamingCrossBoundary() {
        // Construct data such that match crosses Block 1 and Block 2?
        // Or Block 2 match refers to tail of Block 1.
        
        let cStream = LZ4Stream()
        
        let b1 = [UInt8](repeating: 0xAA, count: 100)
        var dst1 = [UInt8](repeating: 0, count: 200)
        let cs1 = LZ4Compress.compress_fast_continue(cStream, src: b1, dst: &dst1)
        
        // Block 2 starts with 0xAA (matches end of b1)
        let b2 = [UInt8](repeating: 0xAA, count: 50)
        var dst2 = [UInt8](repeating: 0, count: 200)
        let cs2 = LZ4Compress.compress_fast_continue(cStream, src: b2, dst: &dst2)
        
        // Verify Decompression
        let dStream = LZ4StreamDecode()
        
        var dec1 = [UInt8](repeating: 0, count: 100)
        let ds1 = LZ4Decompress.decompress_safe_continue(dStream, src: Array(dst1[0..<cs1]), dst: &dec1)
        XCTAssertEqual(dec1, b1)
        
        dStream.setDict(dec1)
        
        var dec2 = [UInt8](repeating: 0, count: 50)
        let ds2 = LZ4Decompress.decompress_safe_continue(dStream, src: Array(dst2[0..<cs2]), dst: &dec2)
        XCTAssertEqual(dec2, b2)
    }
}
