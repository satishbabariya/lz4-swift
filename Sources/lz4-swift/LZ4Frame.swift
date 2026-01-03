//
//  LZ4Frame.swift
//  lz4-swift
//
//  Created for LZ4 Swift Port
//

import Foundation

public enum LZ4Frame {
    
    // Frame Format:
    // Magic Number (4 bytes)
    // Frame Descriptor (3-15 bytes)
    // Data Blocks ...
    // EndMark (4 bytes)
    // Content Checksum (0 or 4 bytes)
    
    public static let MAGIC: UInt32 = 0x184D2204
    public static let MAGIC_SKIPPABLE_START: UInt32 = 0x184D2A50
    public static let MAGIC_SKIPPABLE_MASK: UInt32 = 0xFFFFFFF0
    
    public struct FrameDescriptor {
        public var version: UInt8 = 1 // 01
        public var blockIndependence: Bool = true
        public var blockChecksum: Bool = false
        public var contentSize: Bool = false
        public var contentChecksum: Bool = false // Disabled due to xxHash issues
        public var dictID: Bool = false // Reserved
        public var blockSizeID: UInt8 = 7 // 4MB default
        
        // internal
        func toByte() -> UInt8 {
            var b: UInt8 = (version & 0x3) << 6
            if blockIndependence { b |= (1 << 5) }
            if blockChecksum { b |= (1 << 4) }
            if contentSize { b |= (1 << 3) }
            if contentChecksum { b |= (1 << 2) }
            if dictID { b |= 1 }
            return b
        }
        
        // BD byte
        func bdByte() -> UInt8 {
            return (blockSizeID & 0x7) << 4 // 0...7 -> 4...7 bits. bits 0-3 reserved (0)
        }
    }
    
    public enum Error: Swift.Error {
        case invalidMagic
        case unsupportedVersion
        case corruptedHeader
        case blockChecksumMismatch
        case contentChecksumMismatch
    }
    
    // MARK: - Compression
    
    public static func compress(src: [UInt8]) -> [UInt8] {
        var dst = [UInt8]()
        dst.reserveCapacity(src.count + 64)
        
        // 1. Magic
        write32(&dst, MAGIC)
        
        // 2. FLG Byte
        var desc = FrameDescriptor() // Defaults
        desc.blockIndependence = false // We use streaming compression
        dst.append(desc.toByte())
        
        // 3. BD Byte
        dst.append(desc.bdByte())
        
        // 4. Header Checksum (xxhash32 of FLG+BD, 1 byte)
        // Checksum is (XXH32(bytes) >> 8) & 0xFF
        let headerBytes: [UInt8] = [desc.toByte(), desc.bdByte()]
        let h32 = XXH32.digest(headerBytes, seed: 0)
        dst.append(UInt8((h32 >> 8) & 0xFF))
        
        // 5. Blocks
        var offset = 0
        let blockSize = 1 << (2 * Int(desc.blockSizeID & 0x7) + 8) // maxBlockSize logic?
        // ID 4->64KB, 5->256KB, 6->1MB, 7->4MB.
        // Formula: 1 << (2*ID + 8)?
        // 4: 1 << 16 = 64KB. Correct.
        // 7: 1 << 22 = 4MB. Correct.
        let maxBlockSize = (offset + blockSize > src.count) ? src.count - offset : blockSize // Init logic
        
        // TODO: Loop blocks
        let ctx = LZ4Stream()
        
        while offset < src.count {
            let chunkLen = min(blockSize, src.count - offset)
            let chunk = Array(src[offset..<(offset+chunkLen)])
            
            // Compress
            var compressed = [UInt8](repeating: 0, count: LZ4Compress.compressBound(chunkLen))
            let cSize = LZ4Compress.compress_fast_continue(ctx, src: chunk, dst: &compressed)
            
            // Check expansion
            if cSize > 0 && cSize < chunkLen {
                // Compressed
                write32(&dst, UInt32(cSize)) // High bit 0 = compressed
                dst.append(contentsOf: compressed[0..<cSize])
            } else {
                // Uncompressed
                write32(&dst, UInt32(chunkLen) | 0x80000000) // High bit 1 = uncompressed
                dst.append(contentsOf: chunk)
            }
            
            if desc.blockChecksum {
                // TODO
            }
            
            offset += chunkLen
        }
        
        // 6. EndMark
        write32(&dst, 0)
        
        // 7. Content Checksum
        if desc.contentChecksum {
            let contentH32 = XXH32.digest(src, seed: 0)
            write32(&dst, contentH32)
        }
        
        return dst
    }
    
    private static func write32(_ dst: inout [UInt8], _ val: UInt32) {
        dst.append(UInt8(val & 0xFF))
        dst.append(UInt8((val >> 8) & 0xFF))
        dst.append(UInt8((val >> 16) & 0xFF))
        dst.append(UInt8((val >> 24) & 0xFF))
    }
    
    // MARK: - Decompression
    
    public static func decompress(src: [UInt8]) throws -> [UInt8] {
        var ip = 0
        let iend = src.count
        
        // 1. Magic
        if ip + 4 > iend { throw Error.invalidMagic }
        let magic = read32(src, ip)
        ip += 4
        
        if magic != MAGIC { throw Error.invalidMagic }
        
        // 2. Header
        if ip + 3 > iend { throw Error.corruptedHeader }
        let flg = src[ip]; ip += 1
        let bd = src[ip]; ip += 1
        let headerHC = src[ip]; ip += 1
        
        // Verify Header Checksum
        // Checksum of FLG+BD
        let h32 = XXH32.digest([flg, bd], seed: 0)
        let expectedHC = UInt8((h32 >> 8) & 0xFF)
        if headerHC != expectedHC { throw Error.corruptedHeader }
        
        // Parse FLG
        let version = (flg >> 6) & 0x3
        if version != 1 { throw Error.unsupportedVersion }
        
        let blockIndependence = (flg & (1 << 5)) != 0
        let blockChecksum = (flg & (1 << 4)) != 0
        let contentSize = (flg & (1 << 3)) != 0
        let contentChecksum = (flg & (1 << 2)) != 0
        
        // Content Size (8 bytes) optional
        var cSize: UInt64 = 0
        if contentSize {
            if ip + 8 > iend { throw Error.corruptedHeader }
            // Read 64-bit size (ignore for now, valid frame just has it)
            ip += 8
        }
        
        // 3. Blocks
        let dCtx = LZ4StreamDecode()
        var dst = [UInt8]()
        
        while ip < iend {
            if ip + 4 > iend { throw Error.corruptedHeader }
            let bSizeVal = read32(src, ip); ip += 4
            
            // EndMark
            if bSizeVal == 0 {
                // Content Checksum
                if contentChecksum {
                    if ip + 4 > iend { throw Error.contentChecksumMismatch }
                    let expectedContentHC = read32(src, ip); ip += 4
                    // Verify logic disabled for now as per encoder work
                }
                break
            }
            
            let uncompressed = (bSizeVal & 0x80000000) != 0
            let blockSize = Int(bSizeVal & 0x7FFFFFFF)
            
            if ip + blockSize > iend { throw Error.corruptedHeader }
            
            let blockData = src[ip..<(ip+blockSize)]
            ip += blockSize
            
            if blockChecksum {
                if ip + 4 > iend { throw Error.blockChecksumMismatch }
                ip += 4 // Skip block checksum
            }
            
            if uncompressed {
                dst.append(contentsOf: blockData)
                // Update dict if dependent?
                if !blockIndependence {
                    dCtx.setDict(Array(blockData)) // Simplified
                }
            } else {
                // Decompress
                // We need to estimate output size? Block max size logic?
                // Standard max block is 4MB.
                // We can start with a buffer or use streaming decode.
                // LZ4Decompress.decompress_safe_continue needs destination.
                // Since we don't know exact decompressed size, standard LZ4 frames don't store it per block!
                // Wait. Frame Format does NOT store uncompressed block size.
                // Decoder must handle this.
                // Maximum block size defined in BD byte.
                // BD byte logic earlier...
                
                // Max size based on BD
                let bID = (bd >> 4) & 0x7
                let maxBlockSize = 1 << (2 * Int(bID) + 8)
                
                var decodeBuffer = [UInt8](repeating: 0, count: maxBlockSize)
                let dSize = LZ4Decompress.decompress_safe_continue(dCtx, src: Array(blockData), dst: &decodeBuffer)
                
                if dSize < 0 { throw Error.corruptedHeader } // Decoding error
                let decodedChunk = decodeBuffer[0..<dSize]
                dst.append(contentsOf: decodedChunk)
                
                // Update dict if dependent
                if !blockIndependence {
                    dCtx.setDict(Array(decodedChunk))
                }
            }
        }
        
        return dst
    }
    
    @inline(__always)
    private static func read32(_ src: [UInt8], _ index: Int) -> UInt32 {
        if index + 4 > src.count { return 0 }
        let b0 = UInt32(src[index])
        let b1 = UInt32(src[index+1])
        let b2 = UInt32(src[index+2])
        let b3 = UInt32(src[index+3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
