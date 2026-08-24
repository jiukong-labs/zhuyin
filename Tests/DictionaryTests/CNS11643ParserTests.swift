import CryptoKit
import Foundation
import XCTest

final class CNS11643ParserTests: XCTestCase {
    func testPinnedFirstPartyCharacterSupplement() throws {
        let sourceURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("JiukongCharacters", isDirectory: true)
            .appendingPathComponent("characters.tsv")

        let dataset = try JiukongCharacterParser.parse(sourceURL: sourceURL)

        XCTAssertEqual(
            dataset.statistics,
            JiukongCharacterStatistics(
                entryCount: 3,
                uniqueCharacterCount: 3
            )
        )
        XCTAssertEqual(
            dataset.entries,
            [
                JiukongCharacterEntry(
                    character: "麼",
                    pronunciation: "˙ㄇㄛ"
                ),
                JiukongCharacterEntry(
                    character: "嗎",
                    pronunciation: "ㄇㄚ"
                ),
                JiukongCharacterEntry(
                    character: "框",
                    pronunciation: "ㄎㄨㄤ"
                ),
            ]
        )
    }

    func testFirstPartyCharacterParserRejectsInvalidRows() throws {
        let invalidSources = [
            "麼 ˙ㄇㄛ\n",
            "什麼\t˙ㄇㄛ\n",
            "麼\tASCII\n",
            "麼\t˙ㄇㄛ\n麼\t˙ㄇㄛ\n",
        ]

        for source in invalidSources {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            let sourceURL = directory.appendingPathComponent("characters.tsv")
            try Data(source.utf8).write(to: sourceURL)

            XCTAssertThrowsError(
                try JiukongCharacterParser.parse(sourceURL: sourceURL),
                "Unexpectedly accepted: \(source)"
            )
        }
    }

    func testPinnedFirstPartyPhraseLexiconStatistics() throws {
        let sourceURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("JiukongPhrases", isDirectory: true)
            .appendingPathComponent("phrases.tsv")

        let dataset = try JiukongPhraseParser.parse(sourceURL: sourceURL)

        XCTAssertEqual(
            dataset.statistics,
            JiukongPhraseStatistics(
                entryCount: 1_958,
                uniquePhraseCount: 1_957,
                pronunciationSequenceCount: 1_950
            )
        )
        XCTAssertEqual(dataset.entries.first?.phrase, "測試")
        XCTAssertEqual(
            dataset.entries.first?.pronunciationSequence,
            ["ㄘㄜˋ", "ㄕˋ"]
        )
    }

    func testFirstPartyPhraseReadingsMatchPinnedOfficialCharacterData() throws {
        let phraseURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("JiukongPhrases", isDirectory: true)
            .appendingPathComponent("phrases.tsv")
        let phrases = try JiukongPhraseParser.parse(sourceURL: phraseURL)
        let sourceDirectory = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("CNS11643", isDirectory: true)
            .appendingPathComponent("20260805", isDirectory: true)
        let manifest = try CNS11643Manifest.load(from: sourceDirectory)
        let official = try CNS11643Parser.parse(
            sourceDirectory: sourceDirectory,
            manifest: manifest
        )
        let officialPairs = Set(official.entries.map {
            $0.character + "\u{1F}" + $0.pronunciation
        })

        var mismatches: [String] = []
        for entry in phrases.entries {
            for (index, pair) in zip(
                entry.phrase.map(String.init),
                entry.pronunciationSequence
            ).enumerated() {
                let (character, pronunciation) = pair
                let isDocumentedConversationalVariant = entry.phrase == "謝謝"
                    && entry.pronunciationSequence == ["ㄒㄧㄝˋ", "˙ㄒㄧㄝ"]
                    && index == 1
                guard !isDocumentedConversationalVariant,
                      !officialPairs.contains(
                          character + "\u{1F}" + pronunciation
                      ) else {
                    continue
                }
                mismatches.append(
                    "\(entry.phrase): \(character) \(pronunciation)"
                )
            }
        }

        XCTAssertEqual(mismatches, [])
    }

    func testPinnedMOEIdiomLexiconStatistics() throws {
        let sourceURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("MOEIdioms", isDirectory: true)
            .appendingPathComponent("idioms.tsv")

        let dataset = try JiukongPhraseParser.parse(sourceURL: sourceURL)

        XCTAssertEqual(
            dataset.statistics,
            JiukongPhraseStatistics(
                entryCount: 1_642,
                uniquePhraseCount: 1_642,
                pronunciationSequenceCount: 1_642
            )
        )
        XCTAssertEqual(dataset.entries.first?.phrase, "一毛不拔")
        XCTAssertEqual(
            dataset.entries.first?.pronunciationSequence,
            ["ㄧ", "ㄇㄠˊ", "ㄅㄨˋ", "ㄅㄚˊ"]
        )
    }

    func testMOEIdiomReadingsMatchPinnedOfficialCharacterData() throws {
        let idiomURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("MOEIdioms", isDirectory: true)
            .appendingPathComponent("idioms.tsv")
        let idioms = try JiukongPhraseParser.parse(sourceURL: idiomURL)
        let sourceDirectory = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("CNS11643", isDirectory: true)
            .appendingPathComponent("20260805", isDirectory: true)
        let manifest = try CNS11643Manifest.load(from: sourceDirectory)
        let official = try CNS11643Parser.parse(
            sourceDirectory: sourceDirectory,
            manifest: manifest
        )
        let officialPairs = Set(official.entries.map {
            $0.character + "\u{1F}" + $0.pronunciation
        })

        var mismatches: [String] = []
        for entry in idioms.entries {
            for (character, pronunciation) in zip(
                entry.phrase.map(String.init),
                entry.pronunciationSequence
            ) where !officialPairs.contains(
                character + "\u{1F}" + pronunciation
            ) {
                mismatches.append("\(entry.phrase): \(character) \(pronunciation)")
            }
        }

        XCTAssertEqual(mismatches, [])
    }

    func testPinnedMOERevisedDictionaryPhraseLexiconStatistics() throws {
        let sourceURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("MOERevisedDictionary", isDirectory: true)
            .appendingPathComponent("four-character-phrases.tsv")

        let dataset = try JiukongPhraseParser.parse(sourceURL: sourceURL)

        XCTAssertEqual(
            dataset.statistics,
            JiukongPhraseStatistics(
                entryCount: 33_295,
                uniquePhraseCount: 33_295,
                pronunciationSequenceCount: 32_768
            )
        )
        XCTAssertEqual(dataset.entries.first?.phrase, "八百羅漢")
        XCTAssertEqual(
            dataset.entries.first?.pronunciationSequence,
            ["ㄅㄚ", "ㄅㄞˇ", "ㄌㄨㄛˊ", "ㄏㄢˋ"]
        )
    }

    func testMOERevisedDictionaryReadingsMatchPinnedOfficialCharacterData() throws {
        let revisedURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("MOERevisedDictionary", isDirectory: true)
            .appendingPathComponent("four-character-phrases.tsv")
        let revised = try JiukongPhraseParser.parse(sourceURL: revisedURL)
        let sourceDirectory = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("CNS11643", isDirectory: true)
            .appendingPathComponent("20260805", isDirectory: true)
        let manifest = try CNS11643Manifest.load(from: sourceDirectory)
        let official = try CNS11643Parser.parse(
            sourceDirectory: sourceDirectory,
            manifest: manifest
        )
        // Reading validation must allow the first-party character supplement
        // too (e.g. 框's colloquial ㄎㄨㄤ in 條條框框), because that is
        // exactly what the runtime `dictionary_entries` table this data was
        // validated against actually contains — see
        // `Data/MOERevisedDictionary/README.md`'s extraction note.
        let characterSourceURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("JiukongCharacters", isDirectory: true)
            .appendingPathComponent("characters.tsv")
        let characterSupplement = try JiukongCharacterParser.parse(
            sourceURL: characterSourceURL
        )
        var officialPairs = Set(official.entries.map {
            $0.character + "\u{1F}" + $0.pronunciation
        })
        officialPairs.formUnion(characterSupplement.entries.map {
            $0.character + "\u{1F}" + $0.pronunciation
        })

        var mismatches: [String] = []
        for entry in revised.entries {
            for (character, pronunciation) in zip(
                entry.phrase.map(String.init),
                entry.pronunciationSequence
            ) where !officialPairs.contains(
                character + "\u{1F}" + pronunciation
            ) {
                mismatches.append("\(entry.phrase): \(character) \(pronunciation)")
            }
        }

        XCTAssertEqual(mismatches, [])
    }

    func testMOERevisedDictionaryDoesNotDuplicateEarlierPhraseSources() throws {
        let phraseURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("JiukongPhrases", isDirectory: true)
            .appendingPathComponent("phrases.tsv")
        let idiomURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("MOEIdioms", isDirectory: true)
            .appendingPathComponent("idioms.tsv")
        let revisedURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("MOERevisedDictionary", isDirectory: true)
            .appendingPathComponent("four-character-phrases.tsv")
        let phrases = try JiukongPhraseParser.parse(sourceURL: phraseURL)
        let idioms = try JiukongPhraseParser.parse(sourceURL: idiomURL)
        let revised = try JiukongPhraseParser.parse(sourceURL: revisedURL)

        let merged = try JiukongPhraseDataset.merged(
            firstParty: JiukongPhraseDataset.merged(
                firstParty: phrases,
                governmentSourced: idioms
            ),
            governmentSourced: revised
        )

        XCTAssertEqual(
            merged.statistics.entryCount,
            phrases.statistics.entryCount
                + idioms.statistics.entryCount
                + revised.statistics.entryCount
        )
        XCTAssertEqual(
            merged.entries.suffix(revised.entries.count).map(\.phrase),
            revised.entries.map(\.phrase)
        )
    }

    func testMOEIdiomLexiconDoesNotDuplicateFirstPartyPhrases() throws {
        let phraseURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("JiukongPhrases", isDirectory: true)
            .appendingPathComponent("phrases.tsv")
        let idiomURL = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("MOEIdioms", isDirectory: true)
            .appendingPathComponent("idioms.tsv")
        let phrases = try JiukongPhraseParser.parse(sourceURL: phraseURL)
        let idioms = try JiukongPhraseParser.parse(sourceURL: idiomURL)

        let merged = try JiukongPhraseDataset.merged(
            firstParty: phrases,
            governmentSourced: idioms
        )

        XCTAssertEqual(
            merged.statistics.entryCount,
            phrases.statistics.entryCount + idioms.statistics.entryCount
        )
        XCTAssertEqual(
            merged.entries.suffix(idioms.entries.count).map(\.phrase),
            idioms.entries.map(\.phrase)
        )
    }

    func testPhraseMergeRejectsACrossSourceDuplicate() throws {
        let firstParty = JiukongPhraseDataset(
            entries: [
                JiukongPhraseEntry(
                    phrase: "測試",
                    pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
                    pronunciationKey: DictionaryPronunciationSequenceKey.encode(
                        ["ㄘㄜˋ", "ㄕˋ"]
                    )!,
                    sourceOrder: 0
                ),
            ],
            statistics: JiukongPhraseStatistics(
                entryCount: 1,
                uniquePhraseCount: 1,
                pronunciationSequenceCount: 1
            )
        )
        let governmentSourced = JiukongPhraseDataset(
            entries: [
                JiukongPhraseEntry(
                    phrase: "測試",
                    pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
                    pronunciationKey: DictionaryPronunciationSequenceKey.encode(
                        ["ㄘㄜˋ", "ㄕˋ"]
                    )!,
                    sourceOrder: 0
                ),
            ],
            statistics: JiukongPhraseStatistics(
                entryCount: 1,
                uniquePhraseCount: 1,
                pronunciationSequenceCount: 1
            )
        )

        XCTAssertThrowsError(
            try JiukongPhraseDataset.merged(
                firstParty: firstParty,
                governmentSourced: governmentSourced
            )
        ) { error in
            guard case JiukongPhraseMergeError.duplicateAcrossSources("測試") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testFirstPartyPhraseParserRejectsMalformedAndDuplicateRows() throws {
        let invalidSources = [
            "測試 ㄘㄜˋ ㄕˋ\n",
            "測試\tㄘㄜˋ\n",
            "測試\tASCII ㄕˋ\n",
            "測試\tㄘㄜˋ ㄕˋ\n測試\tㄘㄜˋ ㄕˋ\n",
        ]

        for source in invalidSources {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            let sourceURL = directory.appendingPathComponent("phrases.tsv")
            try Data(source.utf8).write(to: sourceURL)

            XCTAssertThrowsError(
                try JiukongPhraseParser.parse(sourceURL: sourceURL),
                "Unexpectedly accepted: \(source)"
            )
        }
    }

    func testPinnedOfficialSnapshotStatistics() throws {
        let sourceDirectory = repositoryRoot
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("CNS11643", isDirectory: true)
            .appendingPathComponent("20260805", isDirectory: true)
        let manifest = try CNS11643Manifest.load(from: sourceDirectory)
        let dataset = try CNS11643Parser.parse(
            sourceDirectory: sourceDirectory,
            manifest: manifest
        )

        XCTAssertEqual(
            dataset.statistics,
            CNS11643Statistics(
                phoneticRowCount: 117_249,
                uniqueCNSCodeCount: 96_845,
                excludedPrivateUseRowCount: 21_981,
                duplicateEntryCount: 560,
                dictionaryEntryCount: 94_708,
                uniqueCharacterCount: 76_373,
                pronunciationCount: 1_458,
                multiPronunciationCharacterCount: 13_837
            )
        )
    }

    func testJoinsMappingsFiltersPrivateUseAndDeduplicates() throws {
        let fixture = try makeFixture(
            mappings: """
            1-2121\t6211
            1-2122\t884C
            15-2121\tF0001
            """,
            phonetics: """
            1-2121\tㄨㄛˇ
            1-2121\tㄨㄛˇ
            1-2122\tㄒㄧㄥˊ
            1-2122\tㄏㄤˊ
            15-2121\tㄗˋ
            """
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let dataset = try CNS11643Parser.parse(
            sourceDirectory: fixture.directory,
            manifest: fixture.manifest
        )

        XCTAssertEqual(dataset.entries.map(\.character), ["我", "行", "行"])
        XCTAssertEqual(
            dataset.statistics,
            CNS11643Statistics(
                phoneticRowCount: 5,
                uniqueCNSCodeCount: 3,
                excludedPrivateUseRowCount: 1,
                duplicateEntryCount: 1,
                dictionaryEntryCount: 3,
                uniqueCharacterCount: 2,
                pronunciationCount: 3,
                multiPronunciationCharacterCount: 1
            )
        )
    }

    func testRejectsMalformedTSVInsteadOfSkippingIt() throws {
        let fixture = try makeFixture(
            mappings: "1-2121\t6211\n",
            phonetics: "1-2121\tㄨㄛˇ\n\n"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertThrowsError(
            try CNS11643Parser.parse(
                sourceDirectory: fixture.directory,
                manifest: fixture.manifest
            )
        ) { error in
            guard case CNS11643ParserError.malformedLine = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testManifestRejectsChangedSourceFile() throws {
        let fixture = try makeFixture(
            mappings: "1-2121\t6211\n",
            phonetics: "1-2121\tㄨㄛˇ\n"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try writeManifest(
            in: fixture.directory,
            phoneticHash: String(repeating: "0", count: 64),
            mappingHash: sha256(
                of: fixture.directory.appendingPathComponent("mapping.txt")
            )
        )

        XCTAssertThrowsError(
            try CNS11643Manifest.load(from: fixture.directory)
        ) { error in
            guard case CNS11643ManifestError.invalidHash = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testBuilderCreatesAQueryableVersionedDatabase() throws {
        let fixture = try makeFixture(
            mappings: "1-2121\t6211\n1-2122\t884C\n",
            phonetics: "1-2121\tㄨㄛˇ\n1-2122\tㄒㄧㄥˊ\n1-2122\tㄏㄤˊ\n"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try writeManifest(
            in: fixture.directory,
            phoneticHash: sha256(
                of: fixture.directory.appendingPathComponent("phonetic.txt")
            ),
            mappingHash: sha256(
                of: fixture.directory.appendingPathComponent("mapping.txt")
            )
        )

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let outputURL = outputDirectory.appendingPathComponent("fixture.sqlite3")
        let summary = try DictionaryDatabaseBuilder.build(
            sourceDirectory: fixture.directory,
            outputURL: outputURL
        )
        _ = try DictionaryDatabaseBuilder.build(
            sourceDirectory: fixture.directory,
            outputURL: outputURL
        )
        let dictionary = try CharacterDictionary(databaseURL: outputURL)

        XCTAssertEqual(summary.statistics.dictionaryEntryCount, 3)
        XCTAssertEqual(try dictionary.candidates(for: "ㄨㄛˇ"), ["我"])
        XCTAssertEqual(
            try dictionary.pronunciations(for: "行"),
            ["ㄒㄧㄥˊ", "ㄏㄤˊ"]
        )
        XCTAssertEqual(try dictionary.metadataValue(for: "source_version"), "fixture")
        XCTAssertEqual(
            try dictionary.metadataValue(for: "sha256_source_phonetic.txt"),
            try sha256(of: fixture.directory.appendingPathComponent("phonetic.txt"))
        )
    }

    func testRejectsConflictingPrivateAndPublicMappings() throws {
        let fixture = try makeFixture(
            mappings: "1-2121\tF0001\n1-2121\t6211\n",
            phonetics: "1-2121\tㄨㄛˇ\n"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertThrowsError(
            try CNS11643Parser.parse(
                sourceDirectory: fixture.directory,
                manifest: fixture.manifest
            )
        ) { error in
            guard case CNS11643ParserError.conflictingUnicodeMapping = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsNonCanonicalCodesAndPronunciations() throws {
        let invalidFixtures = [
            ("١-2121\t6211\n", "1-2121\tㄨㄛˇ\n"),
            ("1-2121\t+6211\n", "1-2121\tㄨㄛˇ\n"),
            ("1-2121\t6211\n", "1-2121\tㄅㄅ\n"),
            ("1-2121\t6211\n", "1-2121\tㄚㄅ\n")
        ]

        for (mappings, phonetics) in invalidFixtures {
            let fixture = try makeFixture(
                mappings: mappings,
                phonetics: phonetics
            )
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            XCTAssertThrowsError(
                try CNS11643Parser.parse(
                    sourceDirectory: fixture.directory,
                    manifest: fixture.manifest
                )
            )
        }
    }

    func testRejectsEmptyDictionary() throws {
        let fixture = try makeFixture(
            mappings: "1-2121\t6211\n",
            phonetics: ""
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertThrowsError(
            try CNS11643Parser.parse(
                sourceDirectory: fixture.directory,
                manifest: fixture.manifest
            )
        ) { error in
            guard case CNS11643ParserError.emptyDataset = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testBuilderRefusesToReplaceADirectory() throws {
        let fixture = try makeFixture(
            mappings: "1-2121\t6211\n",
            phonetics: "1-2121\tㄨㄛˇ\n"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try writeManifest(
            in: fixture.directory,
            phoneticHash: sha256(
                of: fixture.directory.appendingPathComponent("phonetic.txt")
            ),
            mappingHash: sha256(
                of: fixture.directory.appendingPathComponent("mapping.txt")
            )
        )

        let protectedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: protectedDirectory,
            withIntermediateDirectories: true
        )
        let sentinelURL = protectedDirectory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinelURL)
        defer { try? FileManager.default.removeItem(at: protectedDirectory) }

        XCTAssertThrowsError(
            try DictionaryDatabaseBuilder.build(
                sourceDirectory: fixture.directory,
                outputURL: protectedDirectory
            )
        )
        XCTAssertEqual(try String(contentsOf: sentinelURL, encoding: .utf8), "keep")
    }

    private typealias Fixture = (
        directory: URL,
        manifest: CNS11643Manifest
    )

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeFixture(
        mappings: String,
        phonetics: String
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let mappingName = "mapping.txt"
        let phoneticName = "phonetic.txt"
        try Data(mappings.utf8).write(
            to: directory.appendingPathComponent(mappingName)
        )
        try Data(phonetics.utf8).write(
            to: directory.appendingPathComponent(phoneticName)
        )

        let manifest = CNS11643Manifest(
            version: "fixture",
            retrievedAt: "2026-08-11",
            provider: "Synthetic test fixture",
            datasetName: "Synthetic test fixture",
            datasetURL: "https://example.invalid",
            licenseName: "Test data",
            licenseURL: "https://example.invalid",
            archiveSHA256: [:],
            sourceFiles: [
                CNS11643Manifest.SourceFile(
                    name: phoneticName,
                    role: .phonetic,
                    sha256: String(repeating: "0", count: 64)
                ),
                CNS11643Manifest.SourceFile(
                    name: mappingName,
                    role: .unicodeMapping,
                    sha256: String(repeating: "0", count: 64)
                )
            ]
        )
        return (directory, manifest)
    }

    private func writeManifest(
        in directory: URL,
        phoneticHash: String,
        mappingHash: String
    ) throws {
        let releaseContents = """
        1.檔案名稱：release.txt
          版本：fixture
        """
        let releaseURL = directory.appendingPathComponent("release.txt")
        try Data(releaseContents.utf8).write(to: releaseURL)
        let object: [String: Any] = [
            "version": "fixture",
            "retrievedAt": "2026-08-11",
            "provider": "Synthetic test fixture",
            "datasetName": "Synthetic test fixture",
            "datasetURL": "https://example.invalid",
            "licenseName": "Test data",
            "licenseURL": "https://example.invalid",
            "archiveSHA256": [:],
            "sourceFiles": [
                [
                    "name": "release.txt",
                    "role": "release",
                    "sha256": try sha256(of: releaseURL)
                ],
                [
                    "name": "phonetic.txt",
                    "role": "phonetic",
                    "sha256": phoneticHash
                ],
                [
                    "name": "mapping.txt",
                    "role": "unicodeMapping",
                    "sha256": mappingHash
                ]
            ]
        ]
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: directory.appendingPathComponent("manifest.json"))
    }

    private func sha256(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
