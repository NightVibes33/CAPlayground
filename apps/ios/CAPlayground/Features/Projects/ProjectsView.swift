import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {
    enum DateFilter: String, CaseIterable { case all = "All time", seven = "Last 7 days", thirty = "Last 30 days", year = "This year" }
    enum LocationFilter: String, CaseIterable { case all = "All locations", device = "Device only", cloud = "Cloud only", both = "Device and Cloud" }
    enum SortOrder: String, CaseIterable { case recent = "Newest first", oldest = "Oldest first", nameAscending = "Name A → Z", nameDescending = "Name Z → A" }
    enum ViewMode { case grid, list }
    enum ImportKind { case ca, tendies }

    struct Entry: Identifiable {
        let local: CAProjectDocument?
        let cloud: DriveProject?
        var id: String { local?.id.uuidString ?? "cloud:\(cloud?.id ?? UUID().uuidString)" }
        var name: String { local?.name ?? cloud?.projectName ?? "Project" }
        var storageLocation: String {
            if local != nil && cloud != nil { return "Device and Cloud" }
            return local != nil ? "Device" : "Cloud"
        }
        var date: Date {
            if let local { return local.modifiedAt }
            guard let raw = cloud?.createdTime else { return .distantPast }
            return ISO8601DateFormatter().date(from: raw) ?? .distantPast
        }
    }

    @Environment(ProjectStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(DriveStore.self) private var drive
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @AppStorage("caplayground-tos-accepted") private var tosAccepted = false

    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var dateFilter: DateFilter = .all
    @State private var locationFilter: LocationFilter = .all
    @State private var sortOrder: SortOrder = .recent
    @State private var viewMode: ViewMode = .grid
    @State private var selectMode = false
    @State private var selectedIDs: Set<String> = []
    @State private var createOpen = false
    @State private var importDialogOpen = false
    @State private var importFileOpen = false
    @State private var importKind: ImportKind = .ca
    @State private var importLinkOpen = false
    @State private var importLinkURL = ""
    @State private var importLinkName = ""
    @State private var importLinkCreator = ""
    @State private var importLinkBusy = false
    @State private var importError: String?
    @State private var pendingDelete: Entry?
    @State private var deleteOptionsOpen = false
    @State private var deleteFromDevice = true
    @State private var deleteFromCloud = false
    @State private var pendingRename: CAProjectDocument?
    @State private var renameValue = ""
    @State private var projectName = ""
    @State private var width = 390.0
    @State private var height = 844.0
    @State private var gyroEnabled = false
    @State private var useDeviceBounds = false
    @State private var selectedDeviceName = "iPhone 14"
    @State private var pendingSyncIDs: Set<String> = []

    private var mergedEntries: [Entry] {
        var output: [Entry] = []
        var usedCloud = Set<String>()
        for project in store.projects {
            let match = drive.files.first { $0.projectName.caseInsensitiveCompare(project.name) == .orderedSame }
            if let match { usedCloud.insert(match.id) }
            output.append(Entry(local: project, cloud: match))
        }
        for file in drive.files where !usedCloud.contains(file.id) {
            output.append(Entry(local: nil, cloud: file))
        }
        return output
    }

    private var filteredProjects: [Entry] {
        let calendar = Calendar.current
        let now = Date()
        return mergedEntries.filter { entry in
            let matchesName = query.isEmpty || entry.name.localizedCaseInsensitiveContains(query)
            let matchesDate: Bool = switch dateFilter {
            case .all: true
            case .seven: entry.date >= calendar.date(byAdding: .day, value: -7, to: now)!
            case .thirty: entry.date >= calendar.date(byAdding: .day, value: -30, to: now)!
            case .year: calendar.component(.year, from: entry.date) == calendar.component(.year, from: now)
            }
            let matchesLocation: Bool = switch locationFilter {
            case .all: true
            case .device: entry.local != nil && entry.cloud == nil
            case .cloud: entry.local == nil && entry.cloud != nil
            case .both: entry.local != nil && entry.cloud != nil
            }
            return matchesName && matchesDate && matchesLocation
        }.sorted { lhs, rhs in
            switch sortOrder {
            case .recent: lhs.date > rhs.date
            case .oldest: lhs.date < rhs.date
            case .nameAscending: lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .nameDescending: lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    if let error = importError {
                        Text(error).font(.subheadline).foregroundStyle(.red)
                    }
                    if let message = drive.message {
                        Text(message).font(.subheadline).foregroundStyle(.green)
                    }
                    if let error = drive.error {
                        Text(error).font(.subheadline).foregroundStyle(.red)
                    }
                    projectsSection
                }
                .frame(maxWidth: 1280, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .background(CATheme.background(scheme).ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(for: UUID.self) { id in
                if let project = store.projects.first(where: { $0.id == id }) {
                    EditorView(initialProject: project)
                }
            }
            .sheet(isPresented: $createOpen) { createProjectDialog }
            .sheet(item: $pendingRename) { project in renameProjectDialog(project) }
            .sheet(isPresented: $importLinkOpen) { importLinkDialog }
            .sheet(isPresented: $deleteOptionsOpen) { deleteOptionsDialog }
            .sheet(isPresented: tosBinding) { tosDialog }
            .confirmationDialog("Import Project", isPresented: $importDialogOpen, titleVisibility: .visible) {
                Button("Import .ca / ZIP") { importKind = .ca; importFileOpen = true }
                Button("Import .tendies") { importKind = .tendies; importFileOpen = true }
                Button("Import from Link") { importLinkOpen = true }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose the same import source supported by the CAPlayground website.")
            }
            .fileImporter(isPresented: $importFileOpen, allowedContentTypes: importContentTypes, allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else {
                    if case .failure(let error) = result { importError = error.localizedDescription }
                    return
                }
                importProject(url)
            }
            .confirmationDialog("Delete Project", isPresented: Binding(
                get: { pendingDelete != nil && !deleteOptionsOpen },
                set: { if !$0 && !deleteOptionsOpen { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let entry = pendingDelete { Task { await delete(entry, device: entry.local != nil, cloud: entry.local == nil) } }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { Text("This action cannot be undone.") }
            .task {
                if drive.connected { await drive.refresh() }
            }
            .onChange(of: drive.connected) { _, connected in
                guard connected, !pendingSyncIDs.isEmpty else { return }
                Task { await syncEntries(withIDs: pendingSyncIDs) }
            }
        }
    }

    private var tosBinding: Binding<Bool> {
        Binding(get: { !auth.isSignedIn && !tosAccepted }, set: { _ in })
    }

    private var importContentTypes: [UTType] {
        importKind == .tendies ? [.tendies, .zip] : [.caArchive, .zip]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { dismiss() } label: { Label("Back", systemImage: "arrow.left") }
                .buttonStyle(.plain).font(.subheadline)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 24) { titleAndFilters; actionButtons }
                VStack(alignment: .leading, spacing: 16) { titleAndFilters; actionButtons }
            }
        }
        .padding(.top, 24)
    }

    private var titleAndFilters: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your Projects").font(.system(size: 36, weight: .bold))
            Text("Create and manage your CoreAnimation projects stored locally on your device.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Search projects by name...", text: $query)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 448)
                HStack(spacing: 0) {
                    modeButton(.grid, symbol: "square.grid.3x3")
                    modeButton(.list, symbol: "list.bullet")
                }
                .padding(2).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                Menu {
                    Section("Time Period") {
                        ForEach(DateFilter.allCases, id: \.self) { option in
                            checkButton(option.rawValue, selected: dateFilter == option) { dateFilter = option }
                        }
                    }
                    Section("Storage Location") {
                        ForEach(LocationFilter.allCases, id: \.self) { option in
                            checkButton(option.rawValue, selected: locationFilter == option) { locationFilter = option }
                        }
                    }
                    Section("Sort By") {
                        ForEach(SortOrder.allCases, id: \.self) { option in
                            checkButton(option.rawValue, selected: sortOrder == option) { sortOrder = option }
                        }
                    }
                } label: { Image(systemName: "slider.horizontal.3").frame(width: 38, height: 38) }
                    .buttonStyle(CAWebButtonStyle(variant: .outline, height: 38))
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(selectMode ? "Done" : "Select") {
                selectMode.toggle()
                if !selectMode { selectedIDs.removeAll() }
            }
            .buttonStyle(CAWebButtonStyle(variant: selectMode ? .accent : .outline))

            if selectMode {
                Button("Delete (\(selectedIDs.count))", systemImage: "trash", role: .destructive) {
                    bulkDelete()
                }
                .buttonStyle(CAWebButtonStyle(variant: .outline))
                .foregroundStyle(CATheme.destructive)
                .disabled(selectedIDs.isEmpty)

                Button("Sync to Cloud (\(selectedIDs.count))", systemImage: "cloud") {
                    beginSyncSelected()
                }
                .buttonStyle(CAWebButtonStyle(variant: .outline))
                .disabled(selectedIDs.isEmpty || !selectedEntries.contains(where: { $0.local != nil }))
            } else {
                Button("Import", systemImage: "square.and.arrow.down") { importDialogOpen = true }
                    .buttonStyle(CAWebButtonStyle(variant: .outline))
                Button("New Project", systemImage: "plus") { createOpen = true }
                    .buttonStyle(CAWebButtonStyle(variant: .accent))
            }
        }
    }

    @ViewBuilder private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Projects (\(filteredProjects.count)\(query.isEmpty && dateFilter == .all ? "" : " of \(mergedEntries.count)"))")
                .font(.title3.weight(.semibold))
            if mergedEntries.isEmpty {
                emptyMessage("No projects yet. Create your first project to get started!")
            } else if filteredProjects.isEmpty {
                VStack(spacing: 16) {
                    emptyMessage("No projects match your search/filter.")
                    HStack {
                        if !query.isEmpty { Button("Clear search") { query = "" }.buttonStyle(CAWebButtonStyle(variant: .outline, height: 32)) }
                        if dateFilter != .all { Button("Reset date") { dateFilter = .all }.buttonStyle(CAWebButtonStyle(variant: .outline, height: 32)) }
                    }
                }
            } else if viewMode == .grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                    ForEach(filteredProjects) { entry in projectCard(entry) }
                }
            } else {
                LazyVStack(spacing: 12) { ForEach(filteredProjects) { entry in projectRow(entry) } }
            }
        }
    }

    private func projectCard(_ entry: Entry) -> some View {
        Button { open(entry) } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let project = entry.local {
                            ProjectThumbnail(project: project)
                        } else {
                            ZStack {
                                CATheme.muted(scheme).opacity(0.35)
                                Image(systemName: "cloud.fill").font(.system(size: 42)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    if selectMode { selectionMark(entry) }
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        highlightedName(entry.name)
                            .font(.body.weight(.medium)).lineLimit(1)
                        Text("Created: \(entry.date == .distantPast ? "Unknown" : entry.date.formatted(date: .numeric, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                        Label(entry.storageLocation, systemImage: storageSymbol(entry))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !selectMode {
                        Menu {
                            if let local = entry.local {
                                Button("Rename", systemImage: "pencil") { beginRename(local) }
                                Button("Sync to Cloud", systemImage: "cloud") { beginSync([entry]) }
                            }
                            if let cloud = entry.cloud, entry.local == nil {
                                Button("Download", systemImage: "arrow.down.circle") { Task { await downloadAndOpen(cloud) } }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete(entry) }
                        } label: { Image(systemName: "ellipsis.vertical").frame(width: 32, height: 32) }
                    }
                }
            }
            .padding(16)
            .background(CATheme.card(scheme))
            .clipShape(RoundedRectangle(cornerRadius: CATheme.radius))
            .overlay(RoundedRectangle(cornerRadius: CATheme.radius).stroke(selectedIDs.contains(entry.id) ? CATheme.accent : CATheme.border(scheme), lineWidth: selectedIDs.contains(entry.id) ? 2 : 1))
        }.buttonStyle(.plain)
    }

    private func projectRow(_ entry: Entry) -> some View {
        Button { open(entry) } label: {
            HStack(spacing: 16) {
                Group {
                    if let project = entry.local { ProjectThumbnail(project: project) }
                    else { Image(systemName: "cloud.fill").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity).background(CATheme.muted(scheme).opacity(0.35)) }
                }
                .frame(width: 88, height: 88).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading) {
                    highlightedName(entry.name).fontWeight(.medium)
                    Text("Created: \(entry.date == .distantPast ? "Unknown" : entry.date.formatted(date: .numeric, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(entry.storageLocation, systemImage: storageSymbol(entry)).font(.caption).foregroundStyle(.secondary)
                if selectMode { selectionMark(entry) }
            }.padding(12).caPanel()
        }.buttonStyle(.plain)
    }

    private var createProjectDialog: some View {
        NavigationStack {
            Form {
                Section { TextField("New Wallpaper", text: $projectName) } header: { Text("Project name") }
                Toggle("Set bounds by device", isOn: $useDeviceBounds)
                Toggle("[BETA] Enable Gyro (Parallax Effect)", isOn: $gyroEnabled)
                if useDeviceBounds {
                    Picker("Device", selection: $selectedDeviceName) {
                        ForEach(DeviceSpec.categoryOrder, id: \.self) { category in
                            Section(category) {
                                ForEach(DeviceSpec.all.filter { $0.category == category }) { device in
                                    Text("\(device.name) (\(device.width) × \(device.height))").tag(device.name)
                                }
                            }
                        }
                    }
                    Text("390 × 844 is the most compatible and default for iPhones.").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        TextField("Width (px)", value: $width, format: .number)
                        TextField("Height (px)", value: $height, format: .number)
                    }.keyboardType(.numberPad)
                }
            }
            .navigationTitle("Create New Project").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { createOpen = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") { create() }.disabled(!canCreate) }
            }
        }.presentationDetents([.medium, .large])
    }

    private func renameProjectDialog(_ project: CAProjectDocument) -> some View {
        NavigationStack {
            Form { TextField("Project name", text: $renameValue).textInputAutocapitalization(.words) }
                .navigationTitle("Rename Project").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pendingRename = nil; renameValue = "" } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            var renamed = project
                            renamed.name = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            store.update(renamed)
                            pendingRename = nil
                            renameValue = ""
                        }.disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.presentationDetents([.height(220)])
    }

    private var importLinkDialog: some View {
        NavigationStack {
            Form {
                Section("Wallpaper URL") {
                    TextField("https://…/wallpaper.tendies", text: $importLinkURL)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                }
                Section("Optional attribution") {
                    TextField("Wallpaper name", text: $importLinkName)
                    TextField("Creator", text: $importLinkCreator)
                }
                if importLinkBusy { ProgressView("Downloading and importing…") }
            }
            .navigationTitle("Import from Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { importLinkOpen = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { Task { await importFromLink() } }
                        .disabled(importLinkBusy || URL(string: importLinkURL.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                }
            }
        }.presentationDetents([.medium])
    }

    private var deleteOptionsDialog: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Delete from Device", isOn: $deleteFromDevice)
                    Toggle("Delete from Cloud", isOn: $deleteFromCloud)
                } footer: { Text("Choose where this project should be deleted. This action cannot be undone.") }
            }
            .navigationTitle("Delete Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { deleteOptionsOpen = false; pendingDelete = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete", role: .destructive) {
                        guard let entry = pendingDelete else { return }
                        Task { await delete(entry, device: deleteFromDevice, cloud: deleteFromCloud) }
                    }.disabled(!deleteFromDevice && !deleteFromCloud)
                }
            }
        }.presentationDetents([.height(300)])
    }

    private var tosDialog: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Agree to Terms of Service").font(.title2.bold())
                Text("Please review and accept our Terms of Service before using the project editor while signed out.").foregroundStyle(.secondary)
                NavigationLink("Terms of Service") { TermsOfServiceView() }
                    .buttonStyle(CAWebButtonStyle(variant: .outline))
                Spacer()
                Button("I Agree") { tosAccepted = true }
                    .buttonStyle(CAWebButtonStyle(variant: .accent)).frame(maxWidth: .infinity)
                Button("Back") { dismiss() }
                    .buttonStyle(CAWebButtonStyle(variant: .ghost)).frame(maxWidth: .infinity)
            }.padding(24)
        }.interactiveDismissDisabled()
    }

    private var canCreate: Bool {
        !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (useDeviceBounds || (width > 0 && height > 0))
    }

    private var selectedEntries: [Entry] { mergedEntries.filter { selectedIDs.contains($0.id) } }

    private func beginRename(_ project: CAProjectDocument) { renameValue = project.name; pendingRename = project }

    private func create() {
        let selected = DeviceSpec.all.first { $0.name == selectedDeviceName } ?? DeviceSpec.defaultDevice
        let bounds = useDeviceBounds ? (Double(selected.width), Double(selected.height)) : (width, height)
        let project = store.createProject(name: projectName, width: bounds.0, height: bounds.1, gyroEnabled: gyroEnabled)
        createOpen = false
        projectName = ""
        width = 390
        height = 844
        gyroEnabled = false
        useDeviceBounds = false
        selectedDeviceName = "iPhone 14"
        path.append(project.id)
    }

    private func open(_ entry: Entry) {
        if selectMode {
            if selectedIDs.contains(entry.id) { selectedIDs.remove(entry.id) } else { selectedIDs.insert(entry.id) }
        } else if let project = entry.local {
            path.append(project.id)
        } else if let cloud = entry.cloud {
            Task { await downloadAndOpen(cloud) }
        }
    }

    private func importProject(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            if importKind == .ca, let project = try? JSONDecoder().decode(CAProjectDocument.self, from: data) {
                store.update(project)
                path.append(project.id)
                return
            }
            let suggested = url.deletingPathExtension().lastPathComponent
            let project = try CAArchiveImporter.importProject(data: data, suggestedName: suggested)
            store.update(project)
            path.append(project.id)
            importError = nil
        } catch {
            importError = "Failed to import \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func importFromLink() async {
        guard let url = URL(string: importLinkURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        importLinkBusy = true
        defer { importLinkBusy = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let suggested = importLinkName.trimmingCharacters(in: .whitespacesAndNewlines)
            var project = try CAArchiveImporter.importProject(data: data, suggestedName: suggested.isEmpty ? "Imported Wallpaper" : suggested)
            if !importLinkCreator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                project.documents[project.activeCA]?.camlHeaderComments = "Original wallpaper: \(project.name)\nCreated by: \(importLinkCreator.trimmingCharacters(in: .whitespacesAndNewlines))\nImported from URL"
            }
            store.update(project)
            importLinkOpen = false
            importLinkURL = ""
            importLinkName = ""
            importLinkCreator = ""
            path.append(project.id)
            importError = nil
        } catch {
            importError = "Failed to import wallpaper from link: \(error.localizedDescription)"
        }
    }

    private func confirmDelete(_ entry: Entry) {
        pendingDelete = entry
        if entry.local != nil && entry.cloud != nil {
            deleteFromDevice = true
            deleteFromCloud = false
            deleteOptionsOpen = true
        }
    }

    private func delete(_ entry: Entry, device: Bool, cloud: Bool) async {
        if device, let local = entry.local { store.delete(local) }
        if cloud, let cloudFile = entry.cloud { await drive.delete(cloudFile) }
        pendingDelete = nil
        deleteOptionsOpen = false
        selectedIDs.remove(entry.id)
    }

    private func bulkDelete() {
        let selected = selectedEntries
        for entry in selected where entry.local != nil && entry.cloud == nil {
            if let local = entry.local { store.delete(local) }
        }
        let complex = selected.first { $0.cloud != nil }
        selectedIDs.removeAll()
        if let complex { confirmDelete(complex) }
    }

    private func beginSyncSelected() { beginSync(selectedEntries) }

    private func beginSync(_ entries: [Entry]) {
        let ids = Set(entries.filter { $0.local != nil }.map(\.id))
        guard !ids.isEmpty else { return }
        pendingSyncIDs = ids
        if drive.connected { Task { await syncEntries(withIDs: ids) } }
        else { drive.connect() }
    }

    private func syncEntries(withIDs ids: Set<String>) async {
        let entries = mergedEntries.filter { ids.contains($0.id) }
        for entry in entries {
            if let local = entry.local { _ = await drive.sync(local) }
        }
        pendingSyncIDs.removeAll()
        selectedIDs.removeAll()
        selectMode = false
        await drive.refresh()
    }

    private func downloadAndOpen(_ file: DriveProject) async {
        if let project = await drive.download(file, into: store) { path.append(project.id) }
    }

    private func modeButton(_ mode: ViewMode, symbol: String) -> some View {
        Button { viewMode = mode } label: {
            Image(systemName: symbol).frame(width: 32, height: 32)
                .background(viewMode == mode ? Color.secondary.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }.buttonStyle(.plain)
    }

    private func checkButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: selected ? "checkmark" : "") }
    }

    private func selectionMark(_ entry: Entry) -> some View {
        Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
            .font(.title3).foregroundStyle(selectedIDs.contains(entry.id) ? CATheme.accent : .secondary).padding(8)
    }

    private func emptyMessage(_ text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "folder").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 48)
    }

    @ViewBuilder private func highlightedName(_ name: String) -> some View {
        if query.isEmpty { Text(name) }
        else { Text(name) }
    }

    private func storageSymbol(_ entry: Entry) -> String {
        entry.local != nil && entry.cloud != nil ? "externaldrive.badge.icloud" : entry.cloud != nil ? "cloud" : "internaldrive"
    }
}

private struct ProjectThumbnail: View {
    let project: CAProjectDocument
    var body: some View {
        GeometryReader { geometry in
            let projectWidth = CGFloat(project.width)
            let projectHeight = CGFloat(project.height)
            let scale = min(geometry.size.width / projectWidth, geometry.size.height / projectHeight)
            EditorCanvasRepresentable(project: .constant(project), selectedID: .constant(nil))
                .frame(width: projectWidth * scale, height: projectHeight * scale)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .allowsHitTesting(false)
        }.background(Color(uiColor: UIColor(caHex: project.background) ?? .systemGray6))
    }
}

private struct DeviceSpec: Identifiable, Hashable {
    let name: String
    let width: Int
    let height: Int
    let category: String
    var id: String { name }

    static let categoryOrder = ["iPhone", "iPad", "iPod touch"]
    static let defaultDevice = DeviceSpec(name: "iPhone 14", width: 390, height: 844, category: "iPhone")
    static let all: [DeviceSpec] = [
        .init(name:"iPhone 16 Pro Max",width:440,height:956,category:"iPhone"), .init(name:"iPhone 16 Pro",width:402,height:874,category:"iPhone"), .init(name:"iPhone 16 Plus",width:430,height:932,category:"iPhone"), .init(name:"iPhone 16",width:393,height:852,category:"iPhone"),
        .init(name:"iPhone 15 Pro Max",width:430,height:932,category:"iPhone"), .init(name:"iPhone 15 Pro",width:393,height:852,category:"iPhone"), .init(name:"iPhone 15 Plus",width:430,height:932,category:"iPhone"), .init(name:"iPhone 15",width:393,height:852,category:"iPhone"),
        .init(name:"iPhone 14 Pro Max",width:430,height:932,category:"iPhone"), .init(name:"iPhone 14 Pro",width:393,height:852,category:"iPhone"), .init(name:"iPhone 14 Plus",width:428,height:926,category:"iPhone"), .init(name:"iPhone 14",width:390,height:844,category:"iPhone"),
        .init(name:"iPhone 13 Pro Max",width:428,height:926,category:"iPhone"), .init(name:"iPhone 13 Pro",width:390,height:844,category:"iPhone"), .init(name:"iPhone 13",width:390,height:844,category:"iPhone"), .init(name:"iPhone 13 mini",width:375,height:812,category:"iPhone"),
        .init(name:"iPhone 12 Pro Max",width:428,height:926,category:"iPhone"), .init(name:"iPhone 12 Pro",width:390,height:844,category:"iPhone"), .init(name:"iPhone 12",width:390,height:844,category:"iPhone"), .init(name:"iPhone 12 mini",width:375,height:812,category:"iPhone"),
        .init(name:"iPhone 11 Pro Max",width:414,height:896,category:"iPhone"), .init(name:"iPhone 11 Pro",width:375,height:812,category:"iPhone"), .init(name:"iPhone 11",width:414,height:896,category:"iPhone"), .init(name:"iPhone XS Max",width:414,height:896,category:"iPhone"),
        .init(name:"iPhone XS",width:375,height:812,category:"iPhone"), .init(name:"iPhone XR",width:414,height:896,category:"iPhone"), .init(name:"iPhone X",width:375,height:812,category:"iPhone"), .init(name:"iPhone 8 Plus",width:414,height:736,category:"iPhone"),
        .init(name:"iPhone 8",width:375,height:667,category:"iPhone"), .init(name:"iPhone 7 Plus",width:414,height:736,category:"iPhone"), .init(name:"iPhone 7",width:375,height:667,category:"iPhone"), .init(name:"iPhone 6s Plus",width:414,height:736,category:"iPhone"),
        .init(name:"iPhone 6s",width:375,height:667,category:"iPhone"), .init(name:"iPhone 6 Plus",width:414,height:736,category:"iPhone"), .init(name:"iPhone 6",width:375,height:667,category:"iPhone"), .init(name:"iPhone SE (3rd generation)",width:375,height:667,category:"iPhone"),
        .init(name:"iPhone SE (2nd generation)",width:375,height:667,category:"iPhone"), .init(name:"iPhone SE (1st generation)",width:320,height:568,category:"iPhone"), .init(name:"iPhone 5s",width:320,height:568,category:"iPhone"), .init(name:"iPhone 5c",width:320,height:568,category:"iPhone"),
        .init(name:"iPhone 5",width:320,height:568,category:"iPhone"), .init(name:"iPhone 4s",width:320,height:480,category:"iPhone"), .init(name:"iPhone 4",width:320,height:480,category:"iPhone"), .init(name:"iPhone 3GS",width:320,height:480,category:"iPhone"),
        .init(name:"iPhone 3G",width:320,height:480,category:"iPhone"), .init(name:"iPhone (1st generation)",width:320,height:480,category:"iPhone"),
        .init(name:"iPad Pro 13-inch (M4)",width:1032,height:1376,category:"iPad"), .init(name:"iPad Pro 11-inch (M4)",width:834,height:1210,category:"iPad"), .init(name:"iPad Air 13-inch (M2)",width:1032,height:1376,category:"iPad"), .init(name:"iPad Air 11-inch (M2)",width:834,height:1210,category:"iPad"),
        .init(name:"iPad Pro 12.9-inch (6th generation)",width:1024,height:1366,category:"iPad"), .init(name:"iPad Pro 11-inch (4th generation)",width:834,height:1194,category:"iPad"), .init(name:"iPad (10th generation)",width:820,height:1180,category:"iPad"), .init(name:"iPad Pro 12.9-inch (5th generation)",width:1024,height:1366,category:"iPad"),
        .init(name:"iPad Pro 11-inch (3rd generation)",width:834,height:1194,category:"iPad"), .init(name:"iPad Air (5th generation)",width:820,height:1180,category:"iPad"), .init(name:"iPad (9th generation)",width:810,height:1080,category:"iPad"), .init(name:"iPad mini (6th generation)",width:744,height:1133,category:"iPad"),
        .init(name:"iPad Pro 12.9-inch (4th generation)",width:1024,height:1366,category:"iPad"), .init(name:"iPad Pro 11-inch (2nd generation)",width:834,height:1194,category:"iPad"), .init(name:"iPad (8th generation)",width:810,height:1080,category:"iPad"), .init(name:"iPad Air (4th generation)",width:820,height:1180,category:"iPad"),
        .init(name:"iPad (7th generation)",width:810,height:1080,category:"iPad"), .init(name:"iPad Pro 12.9-inch (3rd generation)",width:1024,height:1366,category:"iPad"), .init(name:"iPad Pro 11-inch (1st generation)",width:834,height:1194,category:"iPad"), .init(name:"iPad Air (3rd generation)",width:834,height:1112,category:"iPad"),
        .init(name:"iPad mini (5th generation)",width:768,height:1024,category:"iPad"), .init(name:"iPad (6th generation)",width:768,height:1024,category:"iPad"), .init(name:"iPad Pro 12.9-inch (2nd generation)",width:1024,height:1366,category:"iPad"), .init(name:"iPad Pro 10.5-inch",width:834,height:1112,category:"iPad"),
        .init(name:"iPad (5th generation)",width:768,height:1024,category:"iPad"), .init(name:"iPad Pro 12.9-inch (1st generation)",width:1024,height:1366,category:"iPad"), .init(name:"iPad Pro 9.7-inch",width:768,height:1024,category:"iPad"), .init(name:"iPad mini 4",width:768,height:1024,category:"iPad"),
        .init(name:"iPad Air 2",width:768,height:1024,category:"iPad"), .init(name:"iPad mini 3",width:768,height:1024,category:"iPad"), .init(name:"iPad Air",width:768,height:1024,category:"iPad"), .init(name:"iPad mini 2",width:768,height:1024,category:"iPad"),
        .init(name:"iPad (4th generation)",width:768,height:1024,category:"iPad"), .init(name:"iPad mini (1st generation)",width:768,height:1024,category:"iPad"), .init(name:"iPad (3rd generation)",width:768,height:1024,category:"iPad"), .init(name:"iPad 2",width:768,height:1024,category:"iPad"), .init(name:"iPad (1st generation)",width:768,height:1024,category:"iPad"),
        .init(name:"iPod touch (7th generation)",width:320,height:568,category:"iPod touch"), .init(name:"iPod touch (6th generation)",width:320,height:568,category:"iPod touch"), .init(name:"iPod touch (5th generation)",width:320,height:568,category:"iPod touch"), .init(name:"iPod touch (4th generation)",width:320,height:480,category:"iPod touch"),
        .init(name:"iPod touch (3rd generation)",width:320,height:480,category:"iPod touch"), .init(name:"iPod touch (2nd generation)",width:320,height:480,category:"iPod touch"), .init(name:"iPod touch (1st generation)",width:320,height:480,category:"iPod touch")
    ]
}

private extension UTType {
    static var caArchive: UTType { UTType(filenameExtension: "ca") ?? .zip }
}
