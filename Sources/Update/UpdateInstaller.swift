import CryptoKit
import Foundation

enum UpdateInstallationError: LocalizedError, Equatable {
    case invalidHTTPResponse
    case serverStatus(Int)
    case requestFailed(String)
    case invalidReleaseAssets
    case invalidChecksumFile
    case checksumPackageNameMismatch
    case checksumMismatch
    case cannotReadPackage
    case cannotPrepareDownload
    case invalidPackageSignature
    case unexpectedPackageSigner
    case packageNotAcceptedByGatekeeper

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "下載伺服器沒有回傳有效的 HTTP 回應。"
        case let .serverStatus(status):
            return "下載伺服器回傳 HTTP \(status)。"
        case let .requestFailed(message):
            return "下載更新失敗：\(message)"
        case .invalidReleaseAssets:
            return "更新檔案名稱或下載網址不正確。"
        case .invalidChecksumFile:
            return "下載的 SHA-256 檢查碼格式不正確。"
        case .checksumPackageNameMismatch:
            return "SHA-256 檢查碼不是提供給這個安裝套件使用。"
        case .checksumMismatch:
            return "安裝套件的 SHA-256 檢查失敗，檔案可能不完整或已被修改。"
        case .cannotReadPackage:
            return "無法讀取下載完成的安裝套件。"
        case .cannotPrepareDownload:
            return "無法建立安全的暫存位置來保存更新。"
        case .invalidPackageSignature:
            return "安裝套件的 Developer ID 簽章無效。"
        case .unexpectedPackageSigner:
            return "安裝套件不是由久空的 Apple Developer Team 簽署。"
        case .packageNotAcceptedByGatekeeper:
            return "macOS Gatekeeper 未接受此安裝套件；套件可能尚未完成 Apple 公證。"
        }
    }
}

enum UpdatePackageChecksum {
    static func expectedDigest(
        from data: Data,
        packageName: String
    ) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw UpdateInstallationError.invalidChecksumFile
        }

        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count == 1 else {
            throw UpdateInstallationError.invalidChecksumFile
        }
        let components = lines[0].split(whereSeparator: \.isWhitespace)
        guard components.count == 2 else {
            throw UpdateInstallationError.invalidChecksumFile
        }

        let digest = String(components[0]).lowercased()
        guard digest.utf8.count == 64,
              digest.utf8.allSatisfy(Self.isLowercaseHexDigit) else {
            throw UpdateInstallationError.invalidChecksumFile
        }

        var statedName = String(components[1])
        if statedName.first == "*" {
            statedName.removeFirst()
        }
        guard URL(fileURLWithPath: statedName).lastPathComponent == packageName else {
            throw UpdateInstallationError.checksumPackageNameMismatch
        }
        return digest
    }

    static func digest(of fileURL: URL) throws -> String {
        guard let stream = InputStream(url: fileURL) else {
            throw UpdateInstallationError.cannotReadPackage
        }

        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw UpdateInstallationError.cannotReadPackage
            }
            if count == 0 {
                break
            }
            hasher.update(data: Data(buffer[..<count]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func isLowercaseHexDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
    }
}

struct UpdateCommandResult {
    let terminationStatus: Int32
    let output: String
}

protocol UpdateCommandRunning {
    func run(executableURL: URL, arguments: [String]) throws -> UpdateCommandResult
}

struct SystemUpdateCommandRunner: UpdateCommandRunning {
    func run(executableURL: URL, arguments: [String]) throws -> UpdateCommandResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData + errorData, encoding: .utf8) ?? ""
        return UpdateCommandResult(
            terminationStatus: process.terminationStatus,
            output: output
        )
    }
}

struct UpdatePackageVerifier {
    static let expectedTeamIdentifier = "6KW8YABG8T"

    private let commandRunner: UpdateCommandRunning

    init(commandRunner: UpdateCommandRunning = SystemUpdateCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func verify(
        packageURL: URL,
        checksumData: Data,
        packageName: String
    ) throws {
        let expectedDigest = try UpdatePackageChecksum.expectedDigest(
            from: checksumData,
            packageName: packageName
        )
        guard try UpdatePackageChecksum.digest(of: packageURL) == expectedDigest else {
            throw UpdateInstallationError.checksumMismatch
        }

        let signature = try commandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/pkgutil"),
            arguments: ["--check-signature", packageURL.path]
        )
        guard signature.terminationStatus == 0 else {
            throw UpdateInstallationError.invalidPackageSignature
        }
        guard Self.hasExpectedInstallerSignature(
            signature.output,
            teamIdentifier: Self.expectedTeamIdentifier
        ) else {
            throw UpdateInstallationError.unexpectedPackageSigner
        }

        let assessment = try commandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/spctl"),
            arguments: ["--assess", "--type", "install", "--verbose=2", packageURL.path]
        )
        guard assessment.terminationStatus == 0 else {
            throw UpdateInstallationError.packageNotAcceptedByGatekeeper
        }
    }

    static func hasExpectedInstallerSignature(
        _ output: String,
        teamIdentifier: String
    ) -> Bool {
        output.split(whereSeparator: \.isNewline).contains { line in
            line.contains("Developer ID Installer:")
                && line.contains("(\(teamIdentifier))")
        }
    }
}

protocol UpdatePackagePreparing {
    func prepare(
        release: UpdateRelease,
        completion: @escaping (Result<URL, Error>) -> Void
    )
}

final class UpdatePackagePreparer: UpdatePackagePreparing {
    static let shared = UpdatePackagePreparer()

    private static let maximumChecksumSize = 4 * 1024

    private let session: URLSession
    private let fileManager: FileManager
    private let verifier: UpdatePackageVerifier

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        verifier: UpdatePackageVerifier = UpdatePackageVerifier()
    ) {
        self.session = session
        self.fileManager = fileManager
        self.verifier = verifier
    }

    func prepare(
        release: UpdateRelease,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let packageName = UpdateRelease.packageName(for: release.version)
        guard release.packageURL.lastPathComponent == packageName,
              release.checksumURL.lastPathComponent == "\(packageName).sha256",
              UpdateRelease.isTrustedDownload(
                  release.packageURL,
                  version: release.version,
                  fileName: packageName
              ),
              UpdateRelease.isTrustedDownload(
                  release.checksumURL,
                  version: release.version,
                  fileName: "\(packageName).sha256"
              ) else {
            finish(.failure(UpdateInstallationError.invalidReleaseAssets), completion: completion)
            return
        }

        session.dataTask(with: request(for: release.checksumURL)) { [weak self] data, response, error in
            guard let self else {
                return
            }
            if let error {
                self.finish(
                    .failure(UpdateInstallationError.requestFailed(error.localizedDescription)),
                    completion: completion
                )
                return
            }
            do {
                try Self.validate(response: response)
                guard let data, data.count <= Self.maximumChecksumSize else {
                    throw UpdateInstallationError.invalidChecksumFile
                }
                _ = try UpdatePackageChecksum.expectedDigest(
                    from: data,
                    packageName: packageName
                )
                self.downloadPackage(
                    release: release,
                    packageName: packageName,
                    checksumData: data,
                    completion: completion
                )
            } catch {
                self.finish(.failure(error), completion: completion)
            }
        }.resume()
    }

    private func downloadPackage(
        release: UpdateRelease,
        packageName: String,
        checksumData: Data,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        session.downloadTask(with: request(for: release.packageURL)) { [weak self] location, response, error in
            guard let self else {
                return
            }
            if let error {
                self.finish(
                    .failure(UpdateInstallationError.requestFailed(error.localizedDescription)),
                    completion: completion
                )
                return
            }

            var updateDirectory: URL?
            do {
                try Self.validate(response: response)
                guard let location else {
                    throw UpdateInstallationError.cannotPrepareDownload
                }

                let directory = fileManager.temporaryDirectory.appendingPathComponent(
                    "Jiukong-Zhuyin-Update-\(UUID().uuidString)",
                    isDirectory: true
                )
                updateDirectory = directory
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
                let packageURL = directory.appendingPathComponent(packageName)
                try fileManager.moveItem(at: location, to: packageURL)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: packageURL.path
                )
                try verifier.verify(
                    packageURL: packageURL,
                    checksumData: checksumData,
                    packageName: packageName
                )
                self.finish(.success(packageURL), completion: completion)
            } catch {
                if let updateDirectory {
                    try? fileManager.removeItem(at: updateDirectory)
                }
                self.finish(.failure(error), completion: completion)
            }
        }.resume()
    }

    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Jiukong-Zhuyin-Updater", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func validate(response: URLResponse?) throws {
        guard let response = response as? HTTPURLResponse else {
            throw UpdateInstallationError.invalidHTTPResponse
        }
        guard response.statusCode == 200 else {
            throw UpdateInstallationError.serverStatus(response.statusCode)
        }
    }

    private func finish(
        _ result: Result<URL, Error>,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
