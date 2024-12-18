extension DirtyJSON {
    class StringIterator {
        public var array: [String]
        public var index = -1

        init(_ text: String) {
            array = text.map { String($0) }
        }

        @discardableResult
        func next() -> String? {
            index += 1
            return index < array.count ? array[index] : nil
        }
        
        @discardableResult
        func prev() -> String? {
            for i in stride(from: index - 1, through: 0, by: -1) {
                let value = array[i]
                if (!value.isEmpty && !DirtyJSON.isWhitespace(value)) {
                    index = i
                    return value
                }
            }
            return nil
        }
        
        func peek(_ n: Int = 1) -> String? {
            guard index < array.count - 1 else {
                return nil
            }
            return array[index + n]
        }
        
        func peekPrev() -> Token {
            for i in stride(from: index - 1, through: 0, by: -1) {
                let value = array[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if (!value.isEmpty && !DirtyJSON.isWhitespace(value)) {
                    return Token(index: i, value: value, lastChar: value.last!.description)
                }
            }
            return Token(index: -1, value: nil, lastChar: nil)
        }
        
        func get() -> String {
            if index >= array.count {
                index = array.count - 1
            }
            return array[index] // Notice: unsafe
        }
        
        func set(_ value: String) {
            if index >= array.count {
                index = array.count - 1
            }
            array[index] = value // Notice: unsafe
        }
        
        func append(_ value: String) {
            if index >= array.count {
                index = array.count - 1
            }
            array[index] = array[index] + value // Notice: unsafe
        }
        
        func done() -> Bool {
            return index >= array.count - 1
        }
        
        func toString() -> String {
            return array.joined(separator: "")
        }
    }
}
