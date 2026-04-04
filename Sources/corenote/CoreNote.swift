import ArgumentParser

@main
struct CoreNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "corenote",
        abstract: "CLI frontend to Apple Notes",
        version: "0.1.0",
        subcommands: []
    )
}
