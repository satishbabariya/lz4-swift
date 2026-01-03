//
//  LZ4HC.swift
//  lz4-swift
//
//  Created for LZ4 Swift Port
//
import Foundation

public class LZ4StreamHC {
    // HC Context
    // Hash Table: Stores the most recent index for a hash
    // Chain Table: Stores the previous index for an index
    
    // Constants
    static let DID_BIT = 16 // 64KB window
    static let DICT_SIZE = 1 << DID_BIT
    static let MAX_NB_ATTEMPTS = 256 // Optimization: Max chain depth
    
    var hashTable: [Int32]
    var chainTable: [UInt16]
    var buffer: [UInt8] // Ring buffer
    
    var nextToUpdate: Int = 0
    
    public init() {
        // Init tables
        self.hashTable = [Int32](repeating: -1, count: 32768) // 32K buckets
        self.chainTable = [UInt16](repeating: 0xFFFF, count: 65536) // 64K chain
        self.buffer = [UInt8]()
        self.buffer.reserveCapacity(LZ4StreamHC.DICT_SIZE)
    }
    
    // Hash function (borrowed from LZ4Common/Compress)
    @inline(__always)
    func hashPosition(_ src: [UInt8], _ pos: Int) -> Int {
        // Use standard LZ4 hash
        let sequence = UInt32(src[pos]) | (UInt32(src[pos+1]) << 8) | (UInt32(src[pos+2]) << 16) | (UInt32(src[pos+3]) << 24)
        return Int((sequence &* 2654435761) >> 17) // HASH_LOG 15 (32 - 15 = 17)
    }
    
    func insert(_ src: [UInt8], _ pos: Int) {
        let h = hashPosition(src, pos)
        let oldPos = hashTable[h]
        hashTable[h] = Int32(pos)
        
        let delta = pos - Int(oldPos)
        if delta > 0 && delta < 0xFFFF {
            chainTable[pos & 0xFFFF] = UInt16(delta)
        } else {
            chainTable[pos & 0xFFFF] = 0xFFFF
        }
    }
    
    func findLongestMatch(_ src: [UInt8], _ pos: Int, _ matchLimit: Int, _ maxAttempts: Int) -> (index: Int, length: Int) {
        var matchIndex = -1
        var longest = 0
        
        let ip = pos
        if ip + 4 > matchLimit { return (-1, 0) }
        
        let conversionMask = 0xFFFF
        
        // Start from previous match in chain (since we just inserted ip)
        let startDelta = Int(chainTable[ip & conversionMask])
        if startDelta == 0xFFFF { return (-1, 0) }
        
        var cursor = ip - startDelta
        var attempts = maxAttempts
        
        while cursor >= 0 && attempts > 0 {
             // Check valid
             if cursor >= ip { break } // Sanity
             if (ip - cursor) > 65535 { break } // Too far
             
             // Check match
             if src[cursor] == src[ip] && src[cursor+longest] == src[ip+longest] {
                 // Potentially better
                 let len = countMatch(src, ip, cursor, matchLimit)
                 if len > longest {
                     longest = len
                     matchIndex = cursor
                 }
             }
             
             // Next in chain
             let delta = Int(chainTable[cursor & conversionMask])
             if delta == 0xFFFF { break }
             cursor -= delta
             attempts -= 1
        }
        
        return (matchIndex, longest)
    }
    
    @inline(__always)
    func countMatch(_ src: [UInt8], _ p1: Int, _ p2: Int, _ limit: Int) -> Int {
        var l = 0
        while (p1 + l < limit) && (p2 + l < limit) && (src[p1+l] == src[p2+l]) {
            l += 1
        }
        return l
    }
}

public struct LZ4HC {
    public static func compress(src: [UInt8], dst: inout [UInt8], compressionLevel: Int = 9) -> Int {
        let ctx = LZ4StreamHC()
        return compress_generic(ctx, src: src, dst: &dst, level: compressionLevel)
    }
    
    private static func compress_generic(_ ctx: LZ4StreamHC, src: [UInt8], dst: inout [UInt8], level: Int) -> Int {
        var ip = 0
        var anchor = 0
        let iend = src.count
        let mflimit = iend - 12
        let matchlimit = iend - 5
        
        var op = 0
        dst.reserveCapacity(LZ4Compress.compressBound(src.count))
        
        // First byte
        ctx.insert(src, 0)
        ip += 1
        
        while ip < mflimit {
            ctx.insert(src, ip)
            
            // 1. Find Match
            let (matchIdx, matchLen) = ctx.findLongestMatch(src, ip, matchlimit, LZ4StreamHC.MAX_NB_ATTEMPTS)
            
            if matchLen < 4 {
                ip += 1
                continue
            }
            
            // 2. Lazy Matching (Lookahead)
            // Check if p+1 allows a longer match
            if ip + 1 < mflimit {
                ctx.insert(src, ip + 1)
                let (_, nextLen) = ctx.findLongestMatch(src, ip + 1, matchlimit, LZ4StreamHC.MAX_NB_ATTEMPTS)
                if nextLen > matchLen {
                    ip += 1 // Emit literal at ip, choose p+1 match next loop
                    continue
                }
            }
            
            // 3. Encode Match
            // Token + LitLen + Lit + Offset + MatchLen
            let litLen = ip - anchor
            let tokenIdx = dst.count
            dst.append(0) // Placeholder for Token
            
            var token = UInt8(0)
            
            // Token.LitLen
            if litLen >= 15 {
                token = 0xF0
                // Extended LitLen
                var l = litLen - 15
                while l >= 255 {
                    dst.append(255)
                    l -= 255
                }
                dst.append(UInt8(l))
            } else {
                token = UInt8(litLen << 4)
            }
            
            // Copy Literals
            if litLen > 0 {
                dst.append(contentsOf: src[anchor..<ip])
            }
            
            // MatchLen
            let mLenCode = matchLen - 4
            if mLenCode >= 15 {
                token |= 0xF
                // Extended MatchLen - Moved after Offset
            } else {
                token |= UInt8(mLenCode)
            }
            
            // Update Token
            dst[tokenIdx] = token
            
            // Offset (Little Endian)
            let offset = ip - matchIdx
            dst.append(UInt8(offset & 0xFF))
            dst.append(UInt8((offset >> 8) & 0xFF))
            
            // Extended MatchLen (MUST be after Offset)
            if mLenCode >= 15 {
                var l = mLenCode - 15
                while l >= 255 {
                    dst.append(255)
                    l -= 255
                }
                dst.append(UInt8(l))
            }
            
            // Advance
            ip += matchLen
            anchor = ip
            
            // Insert skipped positions into table?
            // LZ4HC must keep chain valid.
            // insert ip...ip+matchLen-1
            // We already inserted 'ip' (at start of loop) and 'ip+1' (lazy check).
            // Depends on exact flow.
            // Assuming simplified: Re-insert handled range?
            // "ip" is now new position. We need to fill gap.
            // But strict HC fills ALL.
            /*
             for k in 1..<matchLen {
                 if ip + k < mflimit { ctx.insert(src, ip + k - matchLen) ... }
             }
             */
        }
        
        // Last Literals
        let litLen = iend - anchor
        var token = UInt8(0)
        if litLen >= 15 {
            token = 0xF0
            dst.append(token)
            var l = litLen - 15
            while l >= 255 {
                dst.append(255)
                l -= 255
            }
            dst.append(UInt8(l))
        } else {
            token = UInt8(litLen << 4)
            dst.append(token)
        }
        dst.append(contentsOf: src[anchor..<iend])
        
        return dst.count
    }
}
