import SwiftUI
import UniformTypeIdentifiers

struct PortableConfigDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json, .javaScript, .plainText, .data] }
  static var writableContentTypes: [UTType] { [.json, .javaScript, .plainText] }

  var data: Data

  init(data: Data = Data()) { self.data = data }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    self.data = data
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
