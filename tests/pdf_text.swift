// Prints the extractable text of every page (what search and copy see).
// Usage: swift tests/pdf_text.swift file.pdf
import Foundation
import PDFKit

guard CommandLine.arguments.count > 1,
      let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    print("READ_FAILED"); exit(1)
}
for i in 0..<doc.pageCount {
    print(doc.page(at: i)?.string ?? "")
}
