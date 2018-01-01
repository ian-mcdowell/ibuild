import Foundation

enum CommandError: LocalizedError {
    case error(cmd: String, errCode: Int32)

    var errorDescription: String? {
        switch self {
            case .error(let cmd, let errCode): return "Error while running external command: \(cmd). Return code: \(errCode)"
        }
    }
}

struct Command {

    @discardableResult
    static func exec(_ cmd: String, currentDirectory: String? = nil, env: [String: String]? = nil, _ args: [String]) -> (output: String, error: String, exitCode: Int32) {

        let task = Process()
        task.launchPath = cmd
        task.arguments = args
        if let currentDirectory = currentDirectory {
            task.currentDirectoryPath = currentDirectory
        }
        if let env = env {
            task.environment = mergeEnv(env)
        }

        let outpipe = Pipe()
        task.standardOutput = outpipe
        let errpipe = Pipe()
        task.standardError = errpipe

        task.launch()

        let outdata = outpipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outdata, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)

        let errdata = errpipe.fileHandleForReading.readDataToEndOfFile()
        let error = String(data: errdata, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)

        task.waitUntilExit()
        let status = task.terminationStatus

        return (output, error, status)
    }

    @discardableResult
    static func tryExec(_ cmd: String, currentDirectory: String? = nil, env: [String: String]? = nil, _ args: [String]) throws -> String {
        let result = Command.exec(cmd, currentDirectory: currentDirectory, env: env, args)
        if result.exitCode != 0 {
            throw CommandError.error(cmd: cmd, errCode: result.exitCode)
        }
        return result.output
    }

    @discardableResult
    static func spawn(_ cmd: String, currentDirectory: String? = nil, env: [String: String]? = nil, _ args: [String]) -> Int32 {
        let task = Process()
        task.launchPath = cmd
        task.arguments = args
        if let currentDirectory = currentDirectory {
            task.currentDirectoryPath = currentDirectory
        }
        if let env = env {
            task.environment = mergeEnv(env)
        }

        task.launch()
        task.waitUntilExit()

        return task.terminationStatus
    }

    static func trySpawn(_ cmd: String, currentDirectory: String? = nil, env: [String: String]? = nil, _ args: [String]) throws {
        let result = Command.spawn(cmd, currentDirectory: currentDirectory, env: env, args)
        if result != 0 {
            throw CommandError.error(cmd: cmd, errCode: result)
        }
    }

    static func cp(from: URL, to: URL) throws {
        try Command.trySpawn(
            "/bin/cp",
            ["-R", (from.path as NSString).resolvingSymlinksInPath, (to.path as NSString).resolvingSymlinksInPath]
        )
    }

    private static func mergeEnv(_ env: [String: String]) -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        for (key, value) in env {
            e[key] = value
        }
        return e
    }
}