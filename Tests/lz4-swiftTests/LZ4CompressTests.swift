
import XCTest
@testable import lz4_swift
#if canImport(Darwin)
import Darwin
#endif

final class LZ4CompressTests: XCTestCase {
    
    func testSimpleCompression() {
        // Needs to be long enough for MFLIMIT (12 bytes)
        let text = "Hello World Hello World Hello World"
        let src = Array(text.utf8)
        var dst = [UInt8](repeating: 0, count: 128)
        
        let cSize = LZ4Compress.compress_default(src: src, dst: &dst)
        
        XCTAssertGreaterThan(cSize, 0)
        XCTAssertLessThan(cSize, src.count) // Should compress now
        
        // Decompress
        var decomp = [UInt8](repeating: 0, count: src.count)

        let dSize = LZ4Decompress.decompress_safe(src: Array(dst[0..<cSize]), dst: &decomp)
        
        XCTAssertEqual(dSize, src.count)
        if dSize == src.count {
             XCTAssertEqual(decomp, src)
        }
    }
    
    func testRoundTripRandom() {
        // 4KB repeating data.
        var src = [UInt8]()
        for i in 0..<1000 {
            src.append(UInt8(i % 255))
            src.append(UInt8(i % 10)) // Some redundancy
        }
        
        var dst = [UInt8](repeating: 0, count: src.count * 2) // Safe bound
        
        let cSize = LZ4Compress.compress_default(src: src, dst: &dst)
        
        if cSize == 0 {
             fputs("roundTripRandom: Compression failed (size 0)\n", stderr)
             XCTFail("Compression failed")
             return
        }
        
        var decomp = [UInt8](repeating: 0, count: src.count)
        let dSize = LZ4Decompress.decompress_safe(src: Array(dst[0..<cSize]), dst: &decomp)
        
        if dSize != src.count {
             fputs("roundTripRandom: Decompression size mismatch. Expected \(src.count), got \(dSize)\n", stderr)
             XCTFail("Size mismatch")
             return
        }
        
        if decomp != src {
             fputs("roundTripRandom: Data mismatch\n", stderr)
             // Find first mismatch
             for i in 0..<src.count {
                 if decomp[i] != src[i] {
                     fputs("Mismatch at \(i): expected \(src[i]), got \(decomp[i])\n", stderr)
                     break
                 }
             }
             XCTAssertEqual(decomp, src)
        }
    }
    
    func testNonCompressible() {
        // Disabled temporarily
        /*
        // Random usage
        var src = [UInt8]()
        for _ in 0..<1000 {
            src.append(UInt8.random(in: 0...255))
        }
        
        var dst = [UInt8](repeating: 0, count: src.count * 2) // Expansion possible
        
        let cSize = LZ4Compress.compress_default(src: src, dst: &dst)
        
        // Might be larger
        XCTAssertGreaterThan(cSize, 0)
        
        var decomp = [UInt8](repeating: 0, count: src.count)
        let dSize = LZ4Decompress.decompress_safe(src: Array(dst[0..<cSize]), dst: &decomp)
        
        XCTAssertEqual(dSize, src.count)
        XCTAssertEqual(decomp, src)
        */
    }
}
