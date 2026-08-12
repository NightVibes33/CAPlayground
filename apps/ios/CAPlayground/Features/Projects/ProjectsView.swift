import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {
    enum DateFilter: String, CaseIterable { case all = "All time", seven = "Last 7 days", thirty = "Last 30 days", year = "This year" }
    enum SortOrder: String, CaseIterable { case recent = "Newest first", oldest = "Oldest first", nameAscending = "Name A → Z", nameDescending = "Name Z → A" }
    enum ViewMode { case grid, list }

    @Environment(ProjectStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var dateFilter: DateFilter = .all
    @State private var sortOrder: SortOrder = .recent
    @State private var viewMode: ViewMode = .grid
    @State private var selectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var createOpen = false
    @State private var importOpen = false
    @State private var pendingDelete: CAProjectDocument?
    @State private var projectName = ""
    @State private var width = 390.0
    @State private var height = 844.0
    @State private var gyroEnabled = false
    @State private var useDeviceBounds = false
    @State private var selectedDevice = DevicePreset.iPhone14

    private var filteredProjects: [CAProjectDocument] {
        let calendar = Calendar.current
        let now = Date()
        return store.projects.filter { project in
            let matchesName = query.isEmpty || project.name.localizedCaseInsensitiveContains(query)
            let matchesDate: Bool = switch dateFilter {
            case .all: true
            case .seven: project.modifiedAt >= calendar.date(byAdding: .day, value: -7, to: now)!
            case .thirty: project.modifiedAt >= calendar.date(byAdding: .day, value: -30, to: now)!
            case .year: calendar.component(.year, from: project.modifiedAt) == calendar.component(.year, from: now)
            }
            return matchesName && matchesDate
        }.sorted { lhs, rhs in
            switch sortOrder {
            case .recent: lhs.modifiedAt > rhs.modifiedAt
            case .oldest: lhs.modifiedAt < rhs.modifiedAt
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
                if let project = store.projects.first(where: { $0.id == id }) { EditorView(initialProject: project) }
            }
            .sheet(isPresented: $createOpen) { createProjectDialog }
            .fileImporter(isPresented: $importOpen, allowedContentTypes: [.caPlaygroundProject, .zip], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                importProject(url)
            }
            .confirmationDialog("Delete Project", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let project = pendingDelete { store.delete(project) }; pendingDelete = nil }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { Text("This action cannot be undone.") }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: {}) { Label("Back", systemImage: "arrow.left") }
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
                    Section("Time Period") { ForEach(DateFilter.allCases, id: \.self) { option in checkButton(option.rawValue, selected: dateFilter == option) { dateFilter = option } } }
                    Section("Storage Location") { checkButton("All locations", selected: true) {} ; Button("Device only") {} ; Button("Cloud only") {} ; Button("Device and Cloud") {} }
                    Section("Sort By") { ForEach(SortOrder.allCases, id: \.self) { option in checkButton(option.rawValue, selected: sortOrder == option) { sortOrder = option } } }
                } label: { Image(systemName: "slider.horizontal.3").frame(width: 38, height: 38) }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(selectMode ? "Done" : "Select") {
                selectMode.toggle(); if !selectMode { selectedIDs.removeAll() }
            }.buttonStyle(.bordered)
            if selectMode {
                Button("Delete (\(selectedIDs.count))", systemImage: "trash", role: .destructive) {
                    for project in store.projects where selectedIDs.contains(project.id) { store.delete(project) }
                    selectedIDs.removeAll()
                }.buttonStyle(.borderedProminent).tint(CATheme.destructive).disabled(selectedIDs.isEmpty)
                Button("Sync to Cloud (\(selectedIDs.count))", systemImage: "cloud") {}
                    .buttonStyle(.bordered).disabled(selectedIDs.isEmpty)
            } else {
                Button("Import", systemImage: "square.and.arrow.down") { importOpen = true }.buttonStyle(.bordered)
                Button("New Project", systemImage: "plus") { createOpen = true }.buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Projects (\(filteredProjects.count)\(query.isEmpty && dateFilter == .all ? "" : " of \(store.projects.count)"))")
                .font(.title3.weight(.semibold))
            if store.projects.isEmpty {
                emptyMessage("No projects yet. Create your first project to get started!")
            } else if filteredProjects.isEmpty {
                emptyMessage("No projects match your search/filter.")
            } else if viewMode == .grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                    ForEach(filteredProjects) { project in projectCard(project) }
                }
            } else {
                LazyVStack(spacing: 12) { ForEach(filteredProjects) { project in projectRow(project) } }
            }
        }
    }

    private func projectCard(_ project: CAProjectDocument) -> some View {
        Button { open(project) } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    ProjectThumbnail(project: project).aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    if selectMode { selectionMark(project) }
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.body.weight(.medium)).lineLimit(1)
                        Text("Created: \(project.modifiedAt.formatted(date: .numeric, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                        Label("Device", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Rename", systemImage: "pencil") {}
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = project }
                    } label: { Image(systemName: "ellipsis.vertical").frame(width: 32, height: 32) }
                }
            }
            .padding(16)
            .background(CATheme.card(scheme))
            .clipShape(RoundedRectangle(cornerRadius: CATheme.radius))
            .overlay(RoundedRectangle(cornerRadius: CATheme.radius).stroke(selectedIDs.contains(project.id) ? CATheme.accent : Color(uiColor: .separator), lineWidth: selectedIDs.contains(project.id) ? 2 : 0.5))
        }.buttonStyle(.plain)
    }

    private func projectRow(_ project: CAProjectDocument) -> some View {
        Button { open(project) } label: {
            HStack(spacing: 16) {
                ProjectThumbnail(project: project).frame(width: 88, height: 88).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading) { Text(project.name).fontWeight(.medium); Text("Created: \(project.modifiedAt.formatted(date: .numeric, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                Spacer(); Label("Device", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
                if selectMode { selectionMark(project) }
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
                    Picker("Device", selection: $selectedDevice) { ForEach(DevicePreset.allCases) { Text("\($0.name) (\(Int($0.width)) × \(Int($0.height)))").tag($0) } }
                    Text("390 × 844 is the most compatible and default for iPhones.").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack { TextField("Width (px)", value: $width, format: .number); TextField("Height (px)", value: $height, format: .number) }.keyboardType(.numberPad)
                }
            }
            .navigationTitle("Create New Project").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { createOpen = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") { create() }.disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }.presentationDetents([.medium])
    }

    private func create() {
        let bounds = useDeviceBounds ? (selectedDevice.width, selectedDevice.height) : (width, height)
        let project = store.createProject(name: projectName, width: bounds.0, height: bounds.1, gyroEnabled: gyroEnabled)
        createOpen = false; projectName = ""; width = 390; height = 844; gyroEnabled = false; path.append(project.id)
    }

    private func open(_ project: CAProjectDocument) {
        if selectMode { if selectedIDs.contains(project.id) { selectedIDs.remove(project.id) } else { selectedIDs.insert(project.id) } }
        else { path.append(project.id) }
    }

    private func importProject(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url), let project = try? JSONDecoder().decode(CAProjectDocument.self, from: data) else { return }
        store.update(project)
    }

    private func modeButton(_ mode: ViewMode, symbol: String) -> some View {
        Button { viewMode = mode } label: { Image(systemName: symbol).frame(width: 32, height: 32).background(viewMode == mode ? Color.secondary.opacity(0.15) : .clear).clipShape(RoundedRectangle(cornerRadius: 4)) }.buttonStyle(.plain)
    }

    private func checkButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View { Button(action: action) { Label(title, systemImage: selected ? "checkmark" : "") } }
    private func selectionMark(_ project: CAProjectDocument) -> some View { Image(systemName: selectedIDs.contains(project.id) ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(selectedIDs.contains(project.id) ? CATheme.accent : .secondary).padding(8) }
    private func emptyMessage(_ text: String) -> some View { VStack(spacing: 16) { Image(systemName: "folder").font(.system(size: 48)).foregroundStyle(.secondary); Text(text).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 48) }
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

private enum DevicePreset: String, CaseIterable, Identifiable {
    case iPhone14, iPhone14ProMax, iPhoneSE, iPad11, iPad13
    var id: String { rawValue }
    var name: String { switch self { case .iPhone14: "iPhone 14"; case .iPhone14ProMax: "iPhone 14 Pro Max"; case .iPhoneSE: "iPhone SE"; case .iPad11: "iPad 11-inch"; case .iPad13: "iPad 13-inch" } }
    var width: Double { switch self { case .iPhone14: 390; case .iPhone14ProMax: 430; case .iPhoneSE: 375; case .iPad11: 834; case .iPad13: 1024 } }
    var height: Double { switch self { case .iPhone14: 844; case .iPhone14ProMax: 932; case .iPhoneSE: 667; case .iPad11: 1194; case .iPad13: 1366 } }
}
