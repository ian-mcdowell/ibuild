import Foundation

enum CommandError: LocalizedError {
    case error(cmd: String, errCode: Int32, output: String, error: String)

    var errorDescription: String? {
        switch self {
            case .error(let cmd, let errCode, let output, let error): return "Error while running external command: \(cmd). Return code: \(errCode). Output: \(output), Error: \(error)"
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
            throw CommandError.error(cmd: cmd, errCode: result.exitCode, output: result.output, error: result.error)
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

        let output = Pipe()
        task.standardOutput = output
        task.standardError = output

        task.launch()

        let outdata = output.fileHandleForReading.readDataToEndOfFile()
        let outputStr = String(data: outdata, encoding: .utf8)!

        task.waitUntilExit()

        if task.terminationStatus != 0 {
            print("Command failed: \(cmd)")
            print(outputStr)
        }
        return task.terminationStatus
    }

    static func trySpawn(_ cmd: String, currentDirectory: String? = nil, env: [String: String]? = nil, _ args: [String]) throws {
        let result = Command.spawn(cmd, currentDirectory: currentDirectory, env: env, args)
        if result != 0 {
            throw CommandError.error(cmd: cmd, errCode: result, output: "", error: "")
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
