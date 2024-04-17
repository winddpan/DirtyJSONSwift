extension DirtyJSON {
    public static func fix(_ text: String) -> String {
        let iterator = StringIterator(text)
        // `stack` contains '{' or '['
        var stack: [(index: Int, value: Character)] = []
        // is chars in object key field
        var inObjectKey = false
        // is chars in object value field
        var inObjectValue = false
        
        while true {
            let token = nextToken(iterator)
            let peekPrevResult = iterator.peekPrev()
            
            // update status by `peekPrevResult`
            switch peekPrevResult.lastChar {
                case "{":
                    inObjectKey = true
                    inObjectValue = false
                case "}":
                    inObjectValue = false
                case ":":
                    inObjectKey = false
                    // only ':' can toggle `inObjectValue` to true
                    inObjectValue = true
                case ",":
                    if inObjectValue {
                        inObjectKey = true
                        inObjectValue = false
                    }
                default:
                    break
            }
            
            // when inObjectKey
            var needContinue = false
            if (inObjectKey) {
                switch (token) {
                case "\"", "}", ":", nil:
                        break;
                case "{", "[", "]", ",":
                        // {' or '[' or ']' or ',' is not allow when inObjectKey
                        iterator.set("");
                        needContinue = true
                default:
                    // encounter non-token char that must be quoted
                    // add leading quote
                    iterator.set("\"" + token!)
                    // add trailing quote
                    iterator.set(skipUntilQuotation(iterator)! + "\"")
                    needContinue = true
                }
            }
            if (needContinue) {
                continue
            }

            // not inObjectKey, or token is in '"}:'
            switch token {
            case "\"":
                // encounter quote
                switch (peekPrevResult.lastChar) {
                case ",", "{", "[", ":", nil:
                    iterator.set("\"")
                    // record old index
                    let index0 = iterator.index
                    // find next '"'
                    skipString(iterator)
                    // new index
                    let index1 = iterator.index
                    if (index0 == index1) {
                        // not found
                        iterator.set("")
                    } else if (!iterator.done()) {
                        // found, delete '"' and append '"' to last char
                        iterator.array[index1 - 1] = iterator.array[index1 - 1] + "\""
                        iterator.set("")
                    } else {
                        // end of iterator
                        if (iterator.get() != "\"") {
                            iterator.array[iterator.array.count - 1] = iterator.array.last! + "\""
                        }
                    }
                default:
                    iterator.set("")
                    break
                }
            case "{", "[":
                // encounter '{' or '['
                switch (peekPrevResult.lastChar) {
                case ",", "[", ":", nil:
                    stack.append((index: iterator.index, value: token!.first!))
                default:
                    iterator.set("")
                    break
                }
            case "}", "]":
                // encounter close token '}' or ']'
                switch peekPrevResult.lastChar {
                case ",":
                    // encounter ',}', delete the trailing comma
                    iterator.array[peekPrevResult.index] = ""
                case nil:
                    // encounter something like '   }', delete it
                    iterator.set("")
                default:
                    break
                }
                if stack.isEmpty {
                    // '}' is invalid here, delete it
                    iterator.set("")
                    break
                }
                if stack.popLast()?.value == "{" {
                    // close token should be '}'
                    iterator.set("}")
                    if peekPrevResult.lastChar == ":" {
                        // encounter '...:', change it to '...:null'
                        iterator.array[peekPrevResult.index] = peekPrevResult.value! + "null"
                    }
                } else {
                    // close token should be ']'
                    iterator.set("]")
                }
                inObjectKey = false
                inObjectValue = false
            case ":":
                // encounter ':'
                if stack.isEmpty || stack.last!.value != "{" || inObjectValue || peekPrevResult.lastChar == "{" {
                    // encounter ':' outside of object or when looking for value or the object is empty, delete it
                    iterator.set("")
                    break
                }
            case ",":
                // encounter ','
                switch peekPrevResult.lastChar {
                case "{", "[", ":", ",":
                    // encounter '{,' or '[,' or ':,' or ',,', delete it
                    iterator.set("")
                case nil:
                    // encounter something like '   ,', delete it
                    for i in 0...iterator.index {
                        iterator.array[i] = ""
                    }
                default:
                    // encounter 'someOtherChar,', skip the trailing whitespaces
                    skipWhitespace(iterator, deleteWhitespace: true)
                    switch iterator.peek() {
                    case "}", "]", ",", nil: // encounter ',}' or ',]' or ',,' or ',END'
                        iterator.set("")
                    case ":":
                        // encounter ',:'
                        if inObjectKey {
                            // change to ':'
                            iterator.set("")
                        } else {
                            // change to ','
                            iterator.array[iterator.index + 1] = ""
                        }
                    default:
                        break
                    }
                }
            case nil:
                // encounter end
                switch peekPrevResult.lastChar {
                case ":": // encounter '...:'
                    // change it to '...:null';
                    iterator.array[peekPrevResult.index] = ":null"
                case ",": // encounter '...,'
                    // delete it
                    iterator.array[peekPrevResult.index] = ""
                default:
                    break
                }
                // empty `stack`
                while let value = stack.popLast()?.value {
                    switch value {
                    case "{":
                        // encounter unfinished object
                        iterator.array[iterator.array.count - 1] += "}"
                    case "[":
                        // encounter unfinished array
                        iterator.array[iterator.array.count - 1] += "]"
                    default:
                        break
                    }
                }
                // All Done. Return the fixed compact JSON string
                return iterator.toString()
            default:
                // encounter non-token char
                // not in object key field
                // prepare to get value from index
                let valueIndex0 = iterator.index
                skipUntilToken(iterator)
                let valueIndex1 = iterator.index
                // get value
                let value = iterator.array[valueIndex0...valueIndex1].joined(separator: "")
                
                if DirtyJSON.isNumber(value) {
                    // value is number
                    // do not format number
                    break;
                }
                // value is not number
                switch value.lowercased() {
                case "true", "false", "null":
                    for index in valueIndex0...valueIndex1 {
                        // lower case the bool or null value
                        iterator.array[index] = iterator.array[index].lowercased()
                    }
                default:
                    // value is string, must be quoted
                    iterator.array[valueIndex0] = "\"" + token!
                    iterator.array[valueIndex1] = iterator.get() + "\""
                }
            }
        }
    }

    static func nextToken(_ iterator: StringIterator, deleteWhitespace: Bool = true) -> String? {
        while !iterator.done() {
            // delete whitespaces
            skipWhitespace(iterator, deleteWhitespace: true)
            // find a struct token
            let char = iterator.next()
            switch char {
            case "\"", "'", "`", "“", "”", "‘", "’", "「", "」", "﹁", "﹂", "『", "』", "﹃", "﹄":
                return "\""
            case "【", "〔":
                iterator.set("[")
                return "["
            case "】", "〕":
                iterator.set("]")
                return "]"
            case "：":
                iterator.set(":")
                return ":"
            case "，", "、":
                iterator.set(",")
                return ","
            case "/":
                switch iterator.peek() {
                case "/":
                    // Found '//' comment
                    iterator.set("")
                    while !iterator.done() && iterator.next() != "\n" {
                        iterator.set("") // delete comment
                    }
                    if iterator.get() == "\n" {
                        iterator.set("") // delete \n
                    }
                case "*":
                    // Found '/*' comment
                    iterator.set("") // delete '/'
                    iterator.next() // delete '*'
                    iterator.set("")
                    while !iterator.done() {
                        if iterator.next() == "*" && iterator.peek() == "/" {
                            iterator.set("") // delete '*'
                            iterator.next()
                            iterator.set("") // delete '/'
                            break
                        }
                        iterator.set("")
                    }
                default:
                    break
                }
            case "":
                // char will be empty if we delete it before
                break
            default:
                return char
            }
        }
         // move iterator.index to iterator.array.length
        iterator.next()
        return nil
    }

    static func skipString(_ iterator: StringIterator) {
        while !iterator.done() {
            let char = iterator.next()!
            switch char {
            case "\n":
                iterator.set("\\n")
            case "\t":
                iterator.set("\\t")
            case "\"":
                // encounter quote
                if (hasTrailingTokenOrEnd(iterator)) {
                    // string end
                    return
                }
                iterator.set("\\\"")
            case "'", "`", "“", "”", "‘", "’", "「", "」", "﹁", "﹂", "『", "』", "﹃", "﹄":
                // encounter abnormal quote, and there is a trailing token, change it to '"'
                if (hasTrailingTokenOrEnd(iterator)) {
                    iterator.set("\"");
                    return
                }
            case "\\":
                break
            default:
                // encounter invisible char, delete it
                if isInvisible(char) {
                    iterator.set("")
                }
            }
        }
    }

    static func skipWhitespace(_ iterator: StringIterator, deleteWhitespace: Bool = false) {
        while !iterator.done() {
            guard isWhitespace(iterator.peek()!) else {
                return
            }
            iterator.next()
            if deleteWhitespace {
                iterator.set("")
            }
        }
    }

    static func skipUntilQuotation(_ iterator: StringIterator) -> String? {
        while !iterator.done() {
            let char = iterator.next()
            if char == ":" || char == "：" {
                return iterator.prev()
            }
        }
        return nil
    }

    static func skipUntilToken(_ iterator: StringIterator) {
        while true {
            switch nextToken(iterator) {
            case "{", "}", "[", "]", ":", ",", "\"", nil:
                // move iterator.index back to visible char
                iterator.prev()
                return
            default:
                continue
            }
        }
    }

    static func hasTrailingTokenOrEnd(_ iterator: StringIterator) -> Bool {
        for index in iterator.index + 1 ..< iterator.array.count {
            let value = iterator.array[index]
            if isWhitespace(value) {
                continue
            }
            switch value {
            case "}", "]", ":", ",":
                return true
            default:
                return false
            }
        }
        // end of iterator
        return true
    }
}
