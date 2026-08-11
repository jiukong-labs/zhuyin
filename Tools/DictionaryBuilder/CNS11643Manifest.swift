import CryptoKit
import Foundation

enum CNS11643ManifestError: LocalizedError {
    case invalidFileName(String)
    case invalidHashFormat(file: String, value: String)
    case invalidHash(file: String, expected: String, actual: String)
    case invalidReleaseVersion(file: String, expected: String, actual: String?)
    case invalidRoleConfiguration
    case invalidTextEncoding(String)

    var errorDescription: String? {
        switch self {
        case let .invalidFileName(fileName):
            return "The CNS11643 manifest contains an unsafe file name: \(fileName)"
        case let .invalidHashFormat(file, value):
            return "The CNS11643 manifest has an invalid SHA-256 value for \(file): \(value)"
        case let .invalidHash(file, expected, actual):
            return "SHA-256 mismatch for \(file): expected \(expected), got \(actual)."
        case let .invalidReleaseVersion(file, expected, actual):
            return "CNS11643 release metadata for \(file) has version \(actual ?? "missing"); expected \(expected)."
        case .invalidRoleConfiguration:
            return "The CNS11643 manifest must contain one release file, one phonetic file, and at least one Unicode mapping file."
        case let .invalidTextEncoding(file):
            return "The CNS11643 source file is not valid UTF-8: \(file)"
        }
    }
}

struct CNS11643Manifest: Decodable {
    struct SourceFile: Decodable {
        enum Role: String, Decodable {
            case release
            case phonetic
            case unicodeMapping
        }

        let name: String
        let role: Role
        let sha256: String
    }

    let version: String
    let retrievedAt: String
    let provider: String
    let datasetName: String
    let datasetURL: String
    let licenseName: String
    let licenseURL: String
    let archiveSHA256: [String: String]
    let sourceFiles: [SourceFile]
    private var validatedSourceData: [String: Data]

    init(
        version: String,
        retrievedAt: String,
        provider: String,
        datasetName: String,
        datasetURL: String,
        licenseName: String,
        licenseURL: String,
        archiveSHA256: [String: String],
        sourceFiles: [SourceFile]
    ) {
        self.version = version
        self.retrievedAt = retrievedAt
        self.provider = provider
        self.datasetName = datasetName
        self.datasetURL = datasetURL
        self.licenseName = licenseName
        self.licenseURL = licenseURL
        self.archiveSHA256 = archiveSHA256
        self.sourceFiles = sourceFiles
        validatedSourceData = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case retrievedAt
        case provider
        case datasetName
        case datasetURL
        case licenseName
        case licenseURL
        case archiveSHA256
        case sourceFiles
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decode(String.self, forKey: .version),
            retrievedAt: try container.decode(String.self, forKey: .retrievedAt),
            provider: try container.decode(String.self, forKey: .provider),
            datasetName: try container.decode(String.self, forKey: .datasetName),
            datasetURL: try container.decode(String.self, forKey: .datasetURL),
            licenseName: try container.decode(String.self, forKey: .licenseName),
            licenseURL: try container.decode(String.self, forKey: .licenseURL),
            archiveSHA256: try container.decode(
                [String: String].self,
                forKey: .archiveSHA256
            ),
            sourceFiles: try container.decode(
                [SourceFile].self,
                forKey: .sourceFiles
            )
        )
    }

    static func load(from sourceDirectory: URL) throws -> CNS11643Manifest {
        let manifestURL = sourceDirectory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        var manifest = try JSONDecoder().decode(CNS11643Manifest.self, from: data)
        manifest.validatedSourceData = try manifest.validateFiles(
            in: sourceDirectory
        )
        try manifest.validateReleaseMetadata()
        return manifest
    }

    var releaseFile: SourceFile? {
        sourceFiles.first { $0.role == .release }
    }

    var phoneticFile: SourceFile? {
        sourceFiles.first { $0.role == .phonetic }
    }

    var unicodeMappingFiles: [SourceFile] {
        sourceFiles.filter { $0.role == .unicodeMapping }
    }

    func data(for sourceFile: SourceFile, in sourceDirectory: URL) throws -> Data {
        if let data = validatedSourceData[sourceFile.name] {
            return data
        }

        return try Data(
            contentsOf: sourceDirectory.appendingPathComponent(sourceFile.name)
        )
    }

    private func validateFiles(in sourceDirectory: URL) throws -> [String: Data] {
        let releaseFiles = sourceFiles.filter { $0.role == .release }
        let phoneticFiles = sourceFiles.filter { $0.role == .phonetic }
        guard releaseFiles.count == 1,
              phoneticFiles.count == 1,
              !unicodeMappingFiles.isEmpty,
              !version.isEmpty,
              Set(sourceFiles.map(\.name)).count == sourceFiles.count else {
            throw CNS11643ManifestError.invalidRoleConfiguration
        }

        for (archiveName, hash) in archiveSHA256 {
            guard isSafeFileName(archiveName) else {
                throw CNS11643ManifestError.invalidFileName(archiveName)
            }
            try validateHashFormat(hash, file: archiveName)
        }

        var sourceData: [String: Data] = [:]
        for sourceFile in sourceFiles {
            guard isSafeFileName(sourceFile.name) else {
                throw CNS11643ManifestError.invalidFileName(sourceFile.name)
            }
            try validateHashFormat(sourceFile.sha256, file: sourceFile.name)

            let fileURL = sourceDirectory.appendingPathComponent(sourceFile.name)
            let data = try Data(contentsOf: fileURL)
            let actualHash = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard actualHash == sourceFile.sha256.lowercased() else {
                throw CNS11643ManifestError.invalidHash(
                    file: sourceFile.name,
                    expected: sourceFile.sha256,
                    actual: actualHash
                )
            }
            sourceData[sourceFile.name] = data
        }
        return sourceData
    }

    private func validateReleaseMetadata() throws {
        guard let releaseFile,
              let data = validatedSourceData[releaseFile.name],
              let contents = String(data: data, encoding: .utf8) else {
            throw CNS11643ManifestError.invalidTextEncoding(
                releaseFile?.name ?? "release file"
            )
        }

        let versions = releaseVersions(in: contents)
        for fileName in [releaseFile.name] + archiveSHA256.keys.sorted() {
            let actualVersion = versions[fileName]
            guard actualVersion == version else {
                throw CNS11643ManifestError.invalidReleaseVersion(
                    file: fileName,
                    expected: version,
                    actual: actualVersion
                )
            }
        }
    }

    private func releaseVersions(in contents: String) -> [String: String] {
        var currentFileName: String?
        var versions: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = line.range(of: "檔案名稱：") {
                currentFileName = String(line[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            guard let currentFileName,
                  let range = line.range(of: "版本：") else {
                continue
            }
            versions[currentFileName] = String(line[range.upperBound...])
                .trimmingCharacters(in: .whitespaces)
        }
        return versions
    }

    private func isSafeFileName(_ value: String) -> Bool {
        let lastPathComponent = URL(fileURLWithPath: value).lastPathComponent
        return lastPathComponent == value && value != "." && value != ".."
    }

    private func validateHashFormat(_ value: String, file: String) throws {
        let asciiHexDigits = Set("0123456789abcdefABCDEF".utf8)
        guard value.utf8.count == 64,
              value.utf8.allSatisfy(asciiHexDigits.contains) else {
            throw CNS11643ManifestError.invalidHashFormat(
                file: file,
                value: value
            )
        }
    }
}
