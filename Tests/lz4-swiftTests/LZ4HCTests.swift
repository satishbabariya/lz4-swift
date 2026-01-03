
import XCTest
@testable import lz4_swift

final class LZ4HCTests: XCTestCase {
    
    func testHCSimple() {
        let text = "Hello World Hello World Hello World Hello World Hello World"
        let src = Array(text.utf8)
        var dst = [UInt8]()
        
        let cSize = LZ4HC.compress(src: src, dst: &dst)
        
        XCTAssertGreaterThan(cSize, 0)
        
        // Decompress
        var decompressed = [UInt8](repeating: 0, count: src.count)
        let dSize = LZ4Decompress.decompress_safe(src: Array(dst[0..<cSize]), dst: &decompressed)
        
        XCTAssertEqual(dSize, src.count)
        XCTAssertEqual(decompressed, src)
    }
    
    func testHCPattern() {
        // High redundancy pattern where Lookahead might help?
        // "ABCDE...BCDE..."
        var text = ""
        for _ in 0..<100 {
            text += "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        }
        let src = Array(text.utf8)
        var dstHC = [UInt8]()
        var dstDefault = [UInt8](repeating: 0, count: LZ4Compress.compressBound(src.count))
        
        let cSizeHC = LZ4HC.compress(src: src, dst: &dstHC, compressionLevel: 9)
        let cSizeDefault = LZ4Compress.compress_default(src: src, dst: &dstDefault)
        
        print("Default Size: \(cSizeDefault)")
        print("HC Size: \(cSizeHC)")
        
        XCTAssertTrue(cSizeHC <= cSizeDefault) // HC should be at least as good
        
        var decompressed = [UInt8](repeating: 0, count: src.count)
        let dSize = LZ4Decompress.decompress_safe(src: Array(dstHC[0..<cSizeHC]), dst: &decompressed)
        XCTAssertEqual(dSize, src.count)
        XCTAssertEqual(decompressed, src)
        
        // Verify Default too (sanity check)
        var decompDefault = [UInt8](repeating: 0, count: src.count)
        let dSizeDef = LZ4Decompress.decompress_safe(src: Array(dstDefault[0..<cSizeDefault]), dst: &decompDefault)
        XCTAssertEqual(dSizeDef, src.count)
        XCTAssertEqual(decompDefault, src)
    }
}
