import Foundation

struct DictionarySourceEntry: Equatable {
    let pronunciation: String
    let character: String
    let cnsCode: String
    let sourceOrder: Int64
}

struct CNS11643Statistics: Equatable {
    let phoneticRowCount: Int
    let uniqueCNSCodeCount: Int
    let excludedPrivateUseRowCount: Int
    let duplicateEntryCount: Int
    let dictionaryEntryCount: Int
    let uniqueCharacterCount: Int
    let pronunciationCount: Int
    let multiPronunciationCharacterCount: Int
}

struct CNS11643Dataset {
    let entries: [DictionarySourceEntry]
    let statistics: CNS11643Statistics
}

enum CNS11643ParserError: LocalizedError {
    case emptyDataset
    case invalidTextEncoding(String)
    case malformedLine(file: String, line: Int, contents: String)
    case invalidCNSCode(file: String, line: Int, value: String)
    case invalidUnicodeScalar(file: String, line: Int, value: String)
    case conflictingUnicodeMapping(cnsCode: String)
    case invalidPronunciation(file: String, line: Int, value: String)
    case missingUnicodeMappings([String])

    var errorDescription: String? {
        switch self {
        case .emptyDataset:
            return "The CNS11643 source produced an empty dictionary."
        case let .invalidTextEncoding(file):
            return "The CNS11643 TSV file is not valid UTF-8: \(file)"
        case let .malformedLine(file, line, contents):
            return "Malformed TSV row in \(file):\(line): \(contents)"
        case let .invalidCNSCode(file, line, value):
            return "Invalid CNS code in \(file):\(line): \(value)"
        case let .invalidUnicodeScalar(file, line, value):
            return "Invalid Unicode scalar in \(file):\(line): \(value)"
        case let .conflictingUnicodeMapping(cnsCode):
            return "CNS code \(cnsCode) maps to conflicting Unicode scalars."
        case let .invalidPronunciation(file, line, value):
            return "Invalid Zhuyin pronunciation in \(file):\(line): \(value)"
        case let .missingUnicodeMappings(cnsCodes):
            let preview = cnsCodes.prefix(10).joined(separator: ", ")
            return "Missing Unicode mappings for \(cnsCodes.count) CNS codes: \(preview)"
        }
    }
}

enum CNS11643Parser {
    private struct EntryKey: Hashable {
        let pronunciation: String
        let character: String
    }

    private static let initials = Set("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ")
    private static let medials = Set("ㄧㄨㄩ")
    private static let finals = Set("ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ")
    private static let trailingToneMarks: Set<Character> = ["ˊ", "ˇ", "ˋ"]
    private static let neutralToneMark: Character = "˙"
    private static let asciiDigits = Set("0123456789")
    private static let asciiUppercaseHexDigits = Set("0123456789ABCDEF")

    static func parse(
        sourceDirectory: URL,
        manifest: CNS11643Manifest
    ) throws -> CNS11643Dataset {
        var unicodeByCNSCode: [String: String] = [:]
        var privateUseCNSCodes: Set<String> = []
        var scalarByCNSCode: [String: UInt32] = [:]

        for mappingFile in manifest.unicodeMappingFiles {
            let mappingData = try manifest.data(
                for: mappingFile,
                in: sourceDirectory
            )
            try parseRows(
                data: mappingData,
                fileName: mappingFile.name
            ) { lineNumber, cnsCode, scalarText in
                guard isValidCNSCode(cnsCode) else {
                    throw CNS11643ParserError.invalidCNSCode(
                        file: mappingFile.name,
                        line: lineNumber,
                        value: cnsCode
                    )
                }
                guard (4...6).contains(scalarText.count),
                      scalarText.allSatisfy(asciiUppercaseHexDigits.contains),
                      let scalarValue = UInt32(scalarText, radix: 16),
                      let scalar = UnicodeScalar(scalarValue) else {
                    throw CNS11643ParserError.invalidUnicodeScalar(
                        file: mappingFile.name,
                        line: lineNumber,
                        value: scalarText
                    )
                }

                if let existing = scalarByCNSCode[cnsCode],
                   existing != scalarValue {
                    throw CNS11643ParserError.conflictingUnicodeMapping(
                        cnsCode: cnsCode
                    )
                }
                scalarByCNSCode[cnsCode] = scalarValue

                if isPrivateUse(scalarValue) {
                    privateUseCNSCodes.insert(cnsCode)
                    return
                }

                let character = String(scalar)
                unicodeByCNSCode[cnsCode] = character
            }
        }

        guard let phoneticFile = manifest.phoneticFile else {
            throw CNS11643ManifestError.invalidRoleConfiguration
        }
        let phoneticData = try manifest.data(
            for: phoneticFile,
            in: sourceDirectory
        )
        var entries: [DictionarySourceEntry] = []
        var seenEntries: Set<EntryKey> = []
        var allCNSCodes: Set<String> = []
        var missingCNSCodes: Set<String> = []
        var excludedPrivateUseRowCount = 0
        var duplicateEntryCount = 0
        var phoneticRowCount = 0

        try parseRows(
            data: phoneticData,
            fileName: phoneticFile.name
        ) { lineNumber, cnsCode, pronunciation in
            phoneticRowCount += 1
            allCNSCodes.insert(cnsCode)

            guard isValidCNSCode(cnsCode) else {
                throw CNS11643ParserError.invalidCNSCode(
                    file: phoneticFile.name,
                    line: lineNumber,
                    value: cnsCode
                )
            }
            guard isValidPronunciation(pronunciation) else {
                throw CNS11643ParserError.invalidPronunciation(
                    file: phoneticFile.name,
                    line: lineNumber,
                    value: pronunciation
                )
            }

            guard let character = unicodeByCNSCode[cnsCode] else {
                if privateUseCNSCodes.contains(cnsCode) {
                    excludedPrivateUseRowCount += 1
                } else {
                    missingCNSCodes.insert(cnsCode)
                }
                return
            }

            let key = EntryKey(
                pronunciation: pronunciation,
                character: character
            )
            guard seenEntries.insert(key).inserted else {
                duplicateEntryCount += 1
                return
            }

            entries.append(
                DictionarySourceEntry(
                    pronunciation: pronunciation,
                    character: character,
                    cnsCode: cnsCode,
                    sourceOrder: Int64(lineNumber - 1)
                )
            )
        }

        guard missingCNSCodes.isEmpty else {
            throw CNS11643ParserError.missingUnicodeMappings(
                missingCNSCodes.sorted()
            )
        }
        guard !entries.isEmpty else {
            throw CNS11643ParserError.emptyDataset
        }

        let pronunciations = Set(entries.map(\.pronunciation))
        let pronunciationsByCharacter = Dictionary(
            grouping: entries,
            by: \.character
        )
        let multiPronunciationCharacterCount = pronunciationsByCharacter.values
            .filter { Set($0.map(\.pronunciation)).count > 1 }
            .count

        return CNS11643Dataset(
            entries: entries,
            statistics: CNS11643Statistics(
                phoneticRowCount: phoneticRowCount,
                uniqueCNSCodeCount: allCNSCodes.count,
                excludedPrivateUseRowCount: excludedPrivateUseRowCount,
                duplicateEntryCount: duplicateEntryCount,
                dictionaryEntryCount: entries.count,
                uniqueCharacterCount: pronunciationsByCharacter.count,
                pronunciationCount: pronunciations.count,
                multiPronunciationCharacterCount: multiPronunciationCharacterCount
            )
        )
    }

    private static func parseRows(
        data: Data,
        fileName: String,
        body: (_ lineNumber: Int, _ first: String, _ second: String) throws -> Void
    ) throws {
        guard let contents = String(data: data, encoding: .utf8) else {
            throw CNS11643ParserError.invalidTextEncoding(fileName)
        }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, rawLine) in lines.enumerated() {
            var line = rawLine[...]
            if line.last == "\r" {
                line = line.dropLast()
            }
            if line.isEmpty, offset == lines.count - 1 {
                continue
            }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2 else {
                throw CNS11643ParserError.malformedLine(
                    file: fileName,
                    line: offset + 1,
                    contents: String(line)
                )
            }
            try body(offset + 1, String(fields[0]), String(fields[1]))
        }
    }

    private static func isValidCNSCode(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[0].allSatisfy(asciiDigits.contains),
              parts[1].count == 4 else {
            return false
        }

        return parts[1].allSatisfy(asciiUppercaseHexDigits.contains)
    }

    private static func isValidPronunciation(_ value: String) -> Bool {
        var body = Array(value)
        guard !body.isEmpty else {
            return false
        }

        if body.first == neutralToneMark {
            body.removeFirst()
        } else if let last = body.last, trailingToneMarks.contains(last) {
            body.removeLast()
        }

        guard !body.isEmpty else {
            return false
        }

        var previousSlot = -1
        for symbol in body {
            let slot: Int
            if initials.contains(symbol) {
                slot = 0
            } else if medials.contains(symbol) {
                slot = 1
            } else if finals.contains(symbol) {
                slot = 2
            } else {
                return false
            }

            guard slot > previousSlot else {
                return false
            }
            previousSlot = slot
        }
        return true
    }

    private static func isPrivateUse(_ value: UInt32) -> Bool {
        (0xE000...0xF8FF).contains(value)
            || (0xF0000...0xFFFFD).contains(value)
            || (0x100000...0x10FFFD).contains(value)
    }
}
