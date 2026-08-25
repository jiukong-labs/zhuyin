import Foundation

private enum DictionaryBuilderCommandError: LocalizedError {
    case invalidArguments

    var errorDescription: String? {
        """
        Usage: JiukongDictionaryBuilder --source <CNS snapshot directory> \
        --characters <Jiukong character TSV> --phrases <Jiukong phrase TSV> \
        [--heteronym-tiers <Jiukong heteronym tier TSV>] \
        --output <SQLite database>
        """
    }
}

/// Parses `--flag value` pairs in any order. Every flag takes exactly one
/// value; unknown or malformed flags are rejected rather than silently
/// ignored, since a typo in a builder invocation should fail loudly.
private func parseFlags(
    _ arguments: [String],
    recognizedFlags: Set<String>
) throws -> [String: String] {
    guard arguments.count.isMultiple(of: 2) else {
        throw DictionaryBuilderCommandError.invalidArguments
    }

    var values: [String: String] = [:]
    var index = arguments.startIndex
    while index < arguments.endIndex {
        let flag = arguments[index]
        let value = arguments[index + 1]
        guard recognizedFlags.contains(flag),
              values.updateValue(value, forKey: flag) == nil else {
            throw DictionaryBuilderCommandError.invalidArguments
        }
        index += 2
    }
    return values
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let requiredFlags = ["--source", "--characters", "--phrases", "--output"]
    let optionalFlags = [
        "--heteronym-tiers",
    ]
    let values = try parseFlags(
        arguments,
        recognizedFlags: Set(requiredFlags + optionalFlags)
    )
    guard requiredFlags.allSatisfy({ values[$0] != nil }) else {
        throw DictionaryBuilderCommandError.invalidArguments
    }

    func url(_ flag: String, isDirectory: Bool = false) -> URL? {
        values[flag].map { URL(fileURLWithPath: $0, isDirectory: isDirectory) }
    }

    let summary = try DictionaryDatabaseBuilder.build(
        sourceDirectory: url("--source", isDirectory: true)!,
        characterSourceURL: url("--characters"),
        phraseSourceURL: url("--phrases"),
        heteronymTierURL: url("--heteronym-tiers"),
        outputURL: url("--output")!
    )

    print("Built Jiukong Zhuyin character dictionary:")
    print("  Output: \(summary.outputURL.path)")
    print("  Entries: \(summary.statistics.dictionaryEntryCount)")
    print("  Characters: \(summary.statistics.uniqueCharacterCount)")
    print("  Pronunciations: \(summary.statistics.pronunciationCount)")
    print("  Multi-pronunciation characters: \(summary.statistics.multiPronunciationCharacterCount)")
    print("  Excluded private-use rows: \(summary.statistics.excludedPrivateUseRowCount)")
    print("  Removed duplicate entries: \(summary.statistics.duplicateEntryCount)")
    print("  First-party character readings: \(summary.characterStatistics.entryCount)")
    print("  First-party phrase entries: \(summary.phraseStatistics.entryCount)")
    print("  First-party unique phrases: \(summary.phraseStatistics.uniquePhraseCount)")
    print("  CNS plane 1 characters: \(summary.frequencyTierStatistics.commonCharacterCount)")
    print("  CNS plane 2 characters: \(summary.frequencyTierStatistics.semiCommonCharacterCount)")
    print("  First-party heteronym tier overrides: \(summary.frequencyTierStatistics.heteronymOverrideCount)")
    print("  First-party attested character readings: \(summary.phraseAttestationStatistics.distinctCharacterReadingCount)")
    print("  First-party character-reading attestations: \(summary.phraseAttestationStatistics.totalCharacterReadingCount)")
}

do {
    try run()
} catch {
    let message = "JiukongDictionaryBuilder failed: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}
