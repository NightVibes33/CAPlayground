import Foundation

enum CAExportFormat: String, CaseIterable, Identifiable { case ca, tendies; var id: String { rawValue } }
enum CAExportLicense: String, CaseIterable, Identifiable { case none, attribution = "cc-by-4.0", shareAlike = "cc-by-sa-4.0", nonCommercial = "cc-by-nc-4.0"; var id: String { rawValue } }

enum CAArchiveExporter {
    private static let indexXML = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>rootDocument</key><string>main.caml</string></dict></plist>
"""
    private static let manifest = """<?xml version="1.0" encoding="UTF-8"?>
<caml xmlns="http://www.apple.com/CoreAnimation/1.0"><MicaAssetManifest><modules type="NSArray"/></MicaAssetManifest></caml>
"""

    static func export(project: CAProjectDocument, format: CAExportFormat, license: CAExportLicense) throws -> Data {
        let caEntries = documentEntries(project)
        let licenseData = licenseText(license).map { Data($0.utf8) }
        if format == .ca {
            var entries = caEntries
            if let licenseData { entries.append(.init(path: "LICENSE.txt", data: licenseData)) }
            return ZIPArchive.create(entries: entries)
        }
        let resource = project.gyroEnabled ? "gyro-tendies" : "tendies"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "zip") else { throw CocoaError(.fileNoSuchFile) }
        let template = try Data(contentsOf: url)
        var replacements: [ZIPEntry] = []
        if project.gyroEnabled, let doc = project.documents[.wallpaper] {
            let base = "descriptors/99990000-0000-0000-0000-000000000000/versions/0/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/wallpaper.ca"
            replacements += bundleEntries(doc: doc, project: project, kind: .wallpaper, prefix: base)
        } else {
            if let doc = project.documents[.background] {
                let base = "descriptors/09E9B685-7456-4856-9C10-47DF26B76C33/versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Background-390w-844h@3x~iphone.ca"
                replacements += bundleEntries(doc: doc, project: project, kind: .background, prefix: base)
            }
            if let doc = project.documents[.floating] {
                let base = "descriptors/09E9B685-7456-4856-9C10-47DF26B76C33/versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Floating-390w-844h@3x~iphone.ca"
                replacements += bundleEntries(doc: doc, project: project, kind: .floating, prefix: base)
            }
        }
        if let licenseData { replacements.append(.init(path: "descriptors/LICENSE.txt", data: licenseData)) }
        return try ZIPArchive.replacing(in: template, with: replacements)
    }

    private static func documentEntries(_ project: CAProjectDocument) -> [ZIPEntry] {
        if project.gyroEnabled, let doc = project.documents[.wallpaper] { return bundleEntries(doc: doc, project: project, kind: .wallpaper, prefix: "Wallpaper.ca") }
        return [CADocumentKind.background, .floating].flatMap { kind in project.documents[kind].map { bundleEntries(doc: $0, project: project, kind: kind, prefix: "\(kind.title).ca") } ?? [] }
    }
    private static func bundleEntries(doc: AnimationDocument, project: CAProjectDocument, kind: CADocumentKind, prefix: String) -> [ZIPEntry] {
        [.init(path: "\(prefix)/main.caml", data: Data(CAMLSerializer.serialize(project: project, document: doc, kind: kind).utf8)), .init(path: "\(prefix)/index.xml", data: Data(indexXML.utf8)), .init(path: "\(prefix)/assetManifest.caml", data: Data(manifest.utf8))]
    }
    private static func licenseText(_ license: CAExportLicense) -> String? { license == .none ? nil : "Creative Commons \(license.rawValue)\nSee https://creativecommons.org/licenses/" }
}
