import ArgumentParser
struct FolderGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folder", abstract: "Manage folders",
        subcommands: [FolderListCommand.self, FolderCreateCommand.self, FolderRenameCommand.self, FolderDeleteCommand.self],
        defaultSubcommand: FolderListCommand.self)
}
