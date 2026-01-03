
import XCTest
@testable import lz4_swift

final class LZ4DecompressTests: XCTestCase {
    
    func testSimpleDecompression() {
        // "Hello" uncompressed (Literal)
        // Token: LitLen=5 (0x50) + MatchLen=0 (??)
        // LZ4 Stream: [Token][Lit][...]
        // Token 0x50 = LitLen 5. Matches 0.
        // Data: "Hello"
        // End marker (match offset 0?) -> Wait, block format.
        
        // Let's use correct LZ4 block example.
        // 1. Token: (LitLen=5) << 4 | (MatchLen=0) = 0x50
        // 2. Literals: "Hello"
        // 3. Offset to match: 0 (End) -> Wait, last sequence has specific rules. 
        // Last sequence: "There are specific parsing rules to respect:"
        // "The last sequence is valid only if valid literal length ... and ends with 5 literals"
        // Actually for block format:
        // A block ends when last sequence is processed.
        // Last sequence has ONLY literals (no match).
        // So Token 0x50, "Hello".
        // Then we stop?
        // LZ4 decompressor expects to read match offset unless...
        // "The last sequence ... contains only literals. The match is incompletely defined."
        // Our decompressor code: `if ip >= iend { break }` after literals.
        
        let src: [UInt8] = [
            0x50, // Token: Lit=5
            0x48, 0x65, 0x6C, 0x6C, 0x6F // "Hello"
        ]
        
        var dst = [UInt8](repeating: 0, count: 5)
        
        let res = LZ4Decompress.decompress_safe(src: src, dst: &dst)
        
        XCTAssertEqual(res, 5)
        XCTAssertEqual(String(bytes: dst, encoding: .utf8), "Hello")
    }
    
    func testMatchDecompression() {
        let src: [UInt8] = [
            0x51, // Token
            0x48, 0x65, 0x6C, 0x6C, 0x6F, // "Hello"
            0x05, 0x00, // Offset 5
            0x50, // Token (Last)
            0x57, 0x6F, 0x72, 0x6C, 0x64  // "World"
        ]
        
        var dst = [UInt8](repeating: 0, count: 15)
        
        let res = LZ4Decompress.decompress_safe(src: src, dst: &dst)
        
        XCTAssertEqual(res, 15)
        XCTAssertEqual(String(bytes: dst, encoding: .utf8), "HelloHelloWorld")
    }

    func testMatchDecompressionPartial() {
        // "HelloHelloWorld" -> Target 7
        let src: [UInt8] = [
            0x51, // Token
            0x48, 0x65, 0x6C, 0x6C, 0x6F, // "Hello"
            0x05, 0x00, // Offset 5
            0x50, // Token (Last)
            0x57, 0x6F, 0x72, 0x6C, 0x64  // "World"
        ]
        
        var dst = [UInt8](repeating: 0, count: 15)
        
        // Should decode at least 7 bytes.
        // First block: 5 literals + 5 match = 10 bytes.
        // It stops after 10 bytes because 10 >= 7.
        let res = LZ4Decompress.decompress_safe_partial(src: src, dst: &dst, targetOutputSize: 7)
        
        XCTAssertGreaterThanOrEqual(res, 7)
        XCTAssertEqual(String(bytes: dst[0..<5], encoding: .utf8), "Hello")
    }
}
