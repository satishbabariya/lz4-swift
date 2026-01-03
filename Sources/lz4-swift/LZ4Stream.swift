//
//  LZ4Stream.swift
//  lz4-swift
//
//  Created for LZ4 Swift Port
//

import Foundation

public class LZ4Stream {
    public static let DICT_SIZE = 65536 // 64KB
    
    // State
    internal var hashTable: [Int]
    internal var dict: [UInt8]
    internal var dictSize: Int
    internal var processedBytes: Int
    
    public init() {
        self.hashTable = [Int](repeating: 0, count: LZ4Constants.HASH_SIZE_U32)
        self.dict = [UInt8](repeating: 0, count: LZ4Stream.DICT_SIZE)
        self.dictSize = 0
        self.processedBytes = 0
    }
    
    public func reset() {
        // Reset hash table?
        // Actually, we can just zero it or reset processedBytes?
        // If we reset processedBytes, old hash entries become invalid (or treated as very old).
        // But collisions?
        // Safe bet: clear hash table.
        for i in 0..<hashTable.count { hashTable[i] = 0 }
        self.dictSize = 0
        self.processedBytes = 0
    }
    
    /// Load a dictionary for compression.
    public func loadDict(_ dictionary: [UInt8]) {
        reset()
        // Copy tail of dictionary
        let len = dictionary.count
        if len > LZ4Stream.DICT_SIZE {
            let start = len - LZ4Stream.DICT_SIZE
            // dict = Array(dictionary[start..<len])
            for i in 0..<LZ4Stream.DICT_SIZE {
                dict[i] = dictionary[start + i]
            }
            dictSize = LZ4Stream.DICT_SIZE
        } else {
            for i in 0..<len {
                dict[i] = dictionary[i]
            }
            dictSize = len
        }
        
        // We should also pre-populate Hash Table?
        // LZ4 does this. "Loading" dictionary means hashing it so matches can be found.
        // TODO: Implement hash interaction.
        // For now, simple storage.
    }
}
