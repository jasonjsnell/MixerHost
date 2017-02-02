

import Foundation
///FourCharCode is a typealias of UInt32
extension FourCharCode: ExpressibleByStringLiteral {
    public init(stringLiteral: StringLiteralType) {
        if stringLiteral.utf16.count != 4 {
            fatalError("FourCharCode length must be 4!")
        }
        var code: FourCharCode = 0
        for char in stringLiteral.utf16 {
            if char > 0xFF {
                fatalError("FourCharCode must contain only ASCII characters!")
            }
            code = (code << 8) + FourCharCode(char)
        }
        self = code
    }
    
    public init(extendedGraphemeClusterLiteral value: String) {
        fatalError("FourCharCode must contain 4 ASCII characters!")
    }
    
    public init(unicodeScalarLiteral value: String) {
        fatalError("FourCharCode must contain 4 ASCII characters!")
    }
    
    public init(fromString: String) {
        self.init(stringLiteral: fromString)
    }
    
    public var fourCharString: String {
        let bytes: [CChar] = [
            CChar(truncatingBitPattern: (self >> 24) & 0xFF),
            CChar(truncatingBitPattern: (self >> 16) & 0xFF),
            CChar(truncatingBitPattern: (self >> 8) & 0xFF),
            CChar(truncatingBitPattern: self & 0xFF),
        ]
        let data = NSData(bytes: bytes, length: 4)
        return String(data: data as Data, encoding: String.Encoding.isoLatin1)!
    }
    
    public var possibleFourCharString: String {
        var bytes: [CChar] = [
            CChar(truncatingBitPattern: (self >> 24) & 0xFF),
            CChar(truncatingBitPattern: (self >> 16) & 0xFF),
            CChar(truncatingBitPattern: (self >> 8) & 0xFF),
            CChar(truncatingBitPattern: self & 0xFF),
            0
        ]
        for i in 0..<4 {
            if bytes[i] < 0x20 || bytes[i] > 0x7E {
                bytes[i] = CChar(("?" as UnicodeScalar).value)
            }
        }
        return String(cString:bytes)
    }
}
