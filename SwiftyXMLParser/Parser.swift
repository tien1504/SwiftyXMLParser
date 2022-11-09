/**
 * The MIT License (MIT)
 *
 * Copyright (C) 2016 Yahoo Japan Corporation.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import Foundation
#if canImport(FoundationXML)
    import FoundationXML
#endif

public struct RangeMapping: Codable{
    public let orgRange: Range<Int>
    public let newRange: Range<Int>
    
    init(orgRange: Range<Int>, newRange: Range<Int>) {
        self.orgRange = orgRange
        self.newRange = newRange
    }
}

extension XML {
    class Parser: NSObject, XMLParserDelegate {
        /// If it has value, Parser is interuppted by error. (e.g. using invalid character)
        /// So the result of parsing is missing.
        /// See https://developer.apple.com/documentation/foundation/xmlparser/errorcode
        private(set) var error: XMLError?
        
        private var originalText: String!
        
        private var breakLineIndices: [Int]?
        
        private(set) var text: String = ""
                        
        private var startPoint: (line: Int?, column: Int?)
        
        private(set) var rangeMappings: [RangeMapping] = []

        func parse(_ data: Data) -> Accessor {
            stack = [Element]()
            stack.append(documentRoot)
            text = ""
            rangeMappings = []
            originalText = String(decoding: data, as: UTF8.self)
            breakLineIndices = originalText.breakLineIndices
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.parse()
            //print("###", text)
            //print("###", rangeMappings)
            
            for rangeMapping in rangeMappings{
                let o = originalText[rangeMapping.orgRange]
                let n = text[rangeMapping.newRange]
                assert(n==o)
            }
            if let error = error {
                return Accessor(error)
            } else {
                return Accessor(documentRoot)
            }
        }

        init(trimming manner: CharacterSet? = nil, ignoreNamespaces: Bool = false) {
            self.trimmingManner = manner
            self.ignoreNamespaces = ignoreNamespaces
            self.documentRoot = Element(name: "XML.Parser.AbstructedDocumentRoot", ignoreNamespaces: ignoreNamespaces)
        }
        
        // MARK:- private
        fileprivate var documentRoot: Element
        fileprivate var stack = [Element]()
        fileprivate let trimmingManner: CharacterSet?
        fileprivate let ignoreNamespaces: Bool
        
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
            let node = Element(name: elementName, ignoreNamespaces: ignoreNamespaces)
            node.lineNumberStart = parser.lineNumber
            if !attributeDict.isEmpty {
                node.attributes = attributeDict
            }
            
            let parentNode = stack.last
            
            node.parentElement = parentNode
            parentNode?.childElements.append(node)
            stack.append(node)
            
            // line-column number is at the ">" of the started node
            //let index = originalText.characterIndexFrom(lineNumber: parser.lineNumber, columnNumber: parser.columnNumber, breakLineIndices: breakLineIndices)!
            //print("Begin Element ", elementName, parser.lineNumber, parser.columnNumber, originalText[index])
            startPoint.line = parser.lineNumber
            startPoint.column = parser.columnNumber
            
            // if new paragraph not at the begining of the document
            if elementName == "p" && text.count > 0{
                text.append(.breakLine)
            }
            if elementName == "br"{
                text.append(.breakLine)
            }
        }
        
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if let text = stack.last?.text {
                stack.last?.text = text + string
            } else {
                stack.last?.text = "" + string
            }
            let str = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if str.count > 0{
                // line-column number is at the "<" of the ended node
                // print(str, parser.lineNumber, parser.columnNumber)

                if let startLine = startPoint.line, let startColumn = startPoint.column,
                    let endIndex = originalText.characterIndexFrom(lineNumber: parser.lineNumber, columnNumber: parser.columnNumber, breakLineIndices: breakLineIndices),
                    let startIndex = originalText.characterIndexFrom(lineNumber: startLine, columnNumber: startColumn, breakLineIndices: breakLineIndices){
                    
                    // manually trim newline and whitespace
                    var start = startIndex+1
                    while originalText[start] == .breakLine || originalText[start] == .whitespace{
                        start += 1
                    }
                    var end = endIndex
                    while end-1 > start && (originalText[end-1] == .breakLine || originalText[end-1] == .whitespace){
                        end -= 1
                    }
                    
                    let str2 = originalText[start..<end]//.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
//                    if let last = text.last, !last.isNewline{
//                        text.append(.whitespace)
//                    }
                    
                    let orgRange: Range<Int> = start..<(start+str2.count)
                    let newRange: Range<Int> = text.count..<(text.count+str2.count)
                    rangeMappings.append(RangeMapping(orgRange: orgRange, newRange: newRange))
                    
                    text.append(str2)
                    
                    
                }
            }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            stack.last?.CDATA = CDATABlock
        }
        
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            stack.last?.lineNumberEnd = parser.lineNumber
            if let trimmingManner = self.trimmingManner {
                stack.last?.text = stack.last?.text?.trimmingCharacters(in: trimmingManner)
            }
            stack.removeLast()
            // print("End Element ", elementName, parser.lineNumber, parser.columnNumber)
            // override the startpoint in case of nested element
            startPoint.line = parser.lineNumber
            startPoint.column = parser.columnNumber

        }
        
        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            error = .interruptedParseError(rawError: parseError)
        }
    }
}


public extension String {
    
    static let breakLine = "\n"
    
    static let whitespace = " "
    
    subscript(_ i: Int) -> String {
        let idx1 = index(startIndex, offsetBy: i)
        let idx2 = index(idx1, offsetBy: 1)
        return String(self[idx1..<idx2])
    }
    
    subscript (r: Range<Int>) -> String {
        let start = index(startIndex, offsetBy: r.lowerBound)
        let end = index(startIndex, offsetBy: r.upperBound)
        return String(self[start ..< end])
    }
    
    subscript (r: CountableClosedRange<Int>) -> String {
        let startIndex =  self.index(self.startIndex, offsetBy: r.lowerBound)
        let endIndex = self.index(startIndex, offsetBy: r.upperBound - r.lowerBound)
        return String(self[startIndex...endIndex])
    }
    
    var breakLineIndices: [Int] {
        var lineIndices: [Int] = []
        for (index, c) in self.enumerated(){
            if c == "\n"{
                lineIndices.append(index)
            }
        }
        return lineIndices
    }
    
    /// Calculate character index from line, column number
    /// - Parameters:
    ///   - lineNumber: start from 1
    ///   - columnNumber: start from 1
    /// - Returns: Character index in the string
    func characterIndexFrom(lineNumber: Int, columnNumber: Int, breakLineIndices: [Int]? = nil)->Int?{
        let lineIndices = breakLineIndices ?? self.breakLineIndices
        
        // number of line breaks to get to the lineNumber
        let breakTimes = lineNumber-1
        
        // make sure lineNumber is valid
        guard breakTimes >= 0 && breakTimes-1 < lineIndices.count else {return nil}
        let startIndex = breakTimes-1 >= 0 ? lineIndices[breakTimes-1]+1 : 0 // +1 to pass line break character
        let index = startIndex+columnNumber-1 // -1 because columnNumber start from 1
        
        // make sure columnNumber is valid
        if index >= count {return nil}
        
        return index
    }
}
