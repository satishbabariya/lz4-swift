
import XCTest
import Foundation
@testable import lz4_swift

final class LZ4FrameTests: XCTestCase {
    
    func testCompressFrame() throws {
        let text = "Hello World Hello World Hello World Hello World"
        let data = Array(text.utf8)
        
        let compressed = LZ4Frame.compress(src: data)
        
        XCTAssertGreaterThan(compressed.count, 4) // Magic
        
        // Write to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_frame.lz4")
        try Data(compressed).write(to: tempURL)
        
        print("Written to: \(tempURL.path)")
        
        // Verify with system lz4
        // lz4 -t <file>
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["lz4", "-t", tempURL.path]
        
        try process.run()
        process.waitUntilExit()
        
        XCTAssertEqual(process.terminationStatus, 0, "lz4 -t failed")
        
        // Verify Content
        let decompProcess = Process()
        decompProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        decompProcess.arguments = ["lz4", "-d", "-c", tempURL.path]
        
        let pipe = Pipe()
        decompProcess.standardOutput = pipe
        
        try decompProcess.run()
        decompProcess.waitUntilExit()
        
        XCTAssertEqual(decompProcess.terminationStatus, 0, "lz4 -d failed")
        
        let decompData = pipe.fileHandleForReading.readDataToEndOfFile()
        let decompText = String(data: decompData, encoding: .utf8)
        
        XCTAssertEqual(decompText, text)
    }
    
    func testRoundTrip() throws {
        let text = "Hello World Hello World Hello World Hello World"
        let data = Array(text.utf8)
        
        let compressed = LZ4Frame.compress(src: data)
        let decompressed = try LZ4Frame.decompress(src: compressed)
        
        let result = String(data: Data(decompressed), encoding: .utf8)
        XCTAssertEqual(result, text)
    }
}
