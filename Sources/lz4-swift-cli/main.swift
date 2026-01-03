//
//  main.swift
//  lz4-swift-cli
//
//  Created for LZ4 Swift Port
//

import Foundation
import lz4_swift

func printUsage() {
    print("Usage: lz4-swift-cli <command> <input> <output>")
    print("Commands:")
    print("  compress    Compress input file to output file")
    print("  decompress  Decompress input file to output file")
}

func main() {
    let args = CommandLine.arguments
    if args.count != 4 {
        printUsage()
        exit(1)
    }
    
    let command = args[1]
    let inputPath = args[2]
    let outputPath = args[3]
    
    let inputURL = URL(fileURLWithPath: inputPath)
    let outputURL = URL(fileURLWithPath: outputPath)
    
    do {
        let inputData = try Data(contentsOf: inputURL)
        let inputArray = Array(inputData)
        var outputData: Data
        
        switch command {
        case "compress":
            print("Compressing \(inputPath)...")
            let compressed = LZ4Frame.compress(src: inputArray)
            outputData = Data(compressed)
            print("Compressed: \(inputArray.count) -> \(outputData.count) bytes")
            
        case "decompress":
            print("Decompressing \(inputPath)...")
            let start = ProcessInfo.processInfo.systemUptime
            let decompressed = try LZ4Frame.decompress(src: inputArray)
            let end = ProcessInfo.processInfo.systemUptime
            
            outputData = Data(decompressed)
            print("Decompressed: \(inputArray.count) -> \(outputData.count) bytes")
            print("Time: \(String(format: "%.4f", end - start)) s")
            
        case "benchmark":
            print("Benchmarking \(inputPath)...")
            
            // 1. Swift Compress
            let startC = ProcessInfo.processInfo.systemUptime
            let compressed = LZ4Frame.compress(src: inputArray)
            let endC = ProcessInfo.processInfo.systemUptime
            
            // 2. Swift Decompress
            let startD = ProcessInfo.processInfo.systemUptime
            let _ = try LZ4Frame.decompress(src: compressed)
            let endD = ProcessInfo.processInfo.systemUptime
            
            // 3. Swift HC Compress
            // let startHC = ProcessInfo.processInfo.systemUptime
            // var hcDst = [UInt8]()
            // let _ = LZ4HC.compress(src: inputArray, dst: &hcDst)
            // let endHC = ProcessInfo.processInfo.systemUptime
            
            print("--- Results ---")
            print("Input Size: \(inputArray.count) bytes")
            print("Swift Compress:   \(compressed.count) bytes, \(String(format: "%.4f", endC - startC)) s")
            // print("Swift HC Compress: \(hcDst.count) bytes, \(String(format: "%.4f", endHC - startHC)) s")
            print("Swift Decompress: \(inputArray.count) bytes, \(String(format: "%.4f", endD - startD)) s")
            
            return // Skip writing
            
        default:
            print("Unknown command: \(command)")
            printUsage()
            exit(1)
        }
        
        try outputData.write(to: outputURL)
        print("Written to \(outputPath)")
        
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

main()
