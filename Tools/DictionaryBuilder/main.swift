import Foundation

private enum DictionaryBuilderCommandError: LocalizedError {
    case invalidArguments

    var errorDescription: String? {
        "Usage: JiukongDictionaryBuilder --source <CNS snapshot directory> --phrases <Jiukong phrase TSV> --output <SQLite database>"
    }
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 6,
          arguments[0] == "--source",
          arguments[2] == "--phrases",
          arguments[4] == "--output" else {
        throw DictionaryBuilderCommandError.invalidArguments
    }

    let sourceDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
    let phraseSourceURL = URL(fileURLWithPath: arguments[3])
    let outputURL = URL(fileURLWithPath: arguments[5])
    let summary = try DictionaryDatabaseBuilder.build(
        sourceDirectory: sourceDirectory,
        phraseSourceURL: phraseSourceURL,
        outputURL: outputURL
    )

    print("Built Jiukong Zhuyin character dictionary:")
    print("  Output: \(summary.outputURL.path)")
    print("  Entries: \(summary.statistics.dictionaryEntryCount)")
    print("  Characters: \(summary.statistics.uniqueCharacterCount)")
    print("  Pronunciations: \(summary.statistics.pronunciationCount)")
    print("  Multi-pronunciation characters: \(summary.statistics.multiPronunciationCharacterCount)")
    print("  Excluded private-use rows: \(summary.statistics.excludedPrivateUseRowCount)")
    print("  Removed duplicate entries: \(summary.statistics.duplicateEntryCount)")
    print("  First-party phrase entries: \(summary.phraseStatistics.entryCount)")
    print("  First-party unique phrases: \(summary.phraseStatistics.uniquePhraseCount)")
}

do {
    try run()
} catch {
    let message = "JiukongDictionaryBuilder failed: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}
