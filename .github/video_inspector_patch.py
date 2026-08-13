from pathlib import Path
import re

path = Path('apps/ios/CAPlayground/Features/Editor/InspectorView.swift')
s = path.read_text()

pattern = re.compile(r'''    @ViewBuilder private func video\(_ layer: LayerModel\) -> some View \{.*?\n    \}\n\n    @ViewBuilder private func animations''', re.S)
replacement = r'''    @ViewBuilder private func video(_ layer: LayerModel) -> some View {
        let syncing = layer.syncWithState ?? false
        let frameCount = layer.frameCount ?? 0
        let fps = layer.framesPerSecond ?? 30
        let duration = layer.videoDuration ?? (Double(frameCount) / max(fps, 1))

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Video Properties").font(.subheadline.weight(.medium))
                Text("Frames: \(frameCount)")
                Text("FPS: \(fps.formatted(.number.precision(.fractionLength(0...2))))")
                Text("Duration: \(duration.formatted(.number.precision(.fractionLength(2))))s")
            }
            .font(.subheadline).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Picker("Calculation Mode", selection: optionalString(\.calculationMode, layer.calculationMode ?? "linear")) {
                    Text("Linear").tag("linear")
                    Text("Discrete").tag("discrete")
                }
                .disabled(syncing)
                Text("Linear blends frame values smoothly. Discrete jumps from one frame to the next with no interpolation.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Auto Reverses", isOn: optionalBool(\.autoReverses, layer.autoReverses ?? false))
                    .disabled(syncing)
                Text("When enabled, the video will play forward then backward in a loop.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Sync with state transition", isOn: videoSyncBinding(layer))
                    .disabled(frameCount <= 0 || layer.framePrefix == nil)
                Text("When enabled, the video will sync with state transitions.")
                    .font(.caption2).foregroundStyle(.secondary)

                if syncing {
                    ForEach(["Locked", "Unlock", "Sleep"], id: \.self) { state in
                        Picker("\(state) Frame", selection: videoStateFrameBinding(state, layer: layer)) {
                            Text("Beginning").tag("beginning")
                            Text("End").tag("end")
                        }
                    }
                }
            }
        }
    }

    private func videoSyncBinding(_ layer: LayerModel) -> Binding<Bool> {
        Binding(
            get: { selectedID.flatMap { project.root.find(id: $0) }?.syncWithState ?? layer.syncWithState ?? false },
            set: { enabled in setVideoStateSync(enabled, snapshot: layer) }
        )
    }

    private func setVideoStateSync(_ enabled: Bool, snapshot: LayerModel) {
        guard let selectedID, let current = project.root.find(id: selectedID) else { return }
        let oldFrameIDs = Set(current.children.map(\.id))
        removeVideoFrameOverrides(targetIDs: oldFrameIDs)

        guard enabled else {
            project.root.update(id: selectedID) { video in
                video.syncWithState = false
                video.children = []
                video.syncStateFrameMode = [:]
            }
            return
        }

        let count = current.frameCount ?? snapshot.frameCount ?? 0
        guard count > 0, let prefix = current.framePrefix ?? snapshot.framePrefix else { return }
        let rawExtension = current.frameExtension ?? snapshot.frameExtension ?? ".jpg"
        let ext = rawExtension.hasPrefix(".") ? rawExtension : ".\(rawExtension)"
        var children: [LayerModel] = []
        for index in 0..<count {
            var child = LayerModel(
                id: UUID(),
                name: "\(current.id.uuidString)_frame_\(index)",
                kind: .image,
                position: .init(x: current.size.width / 2, y: current.size.height / 2),
                size: current.size
            )
            child.imageName = "\(prefix)\(index)\(ext)"
            child.contentMode = "fill"
            child.zPosition = videoInitialZ(index)
            children.append(child)
        }
        let modes = ["Locked": "beginning", "Unlock": "end", "Sleep": "beginning"]
        project.root.update(id: selectedID) { video in
            video.syncWithState = true
            video.children = children
            video.syncStateFrameMode = modes
        }
        applyVideoFrameOverrides(children: children, modes: modes)
    }

    private func videoStateFrameBinding(_ state: String, layer: LayerModel) -> Binding<String> {
        Binding(
            get: {
                let current = selectedID.flatMap { project.root.find(id: $0) }
                let fallback = state == "Unlock" ? "end" : "beginning"
                return current?.syncStateFrameMode?[state] ?? layer.syncStateFrameMode?[state] ?? fallback
            },
            set: { mode in setVideoStateFrameMode(state: state, mode: mode) }
        )
    }

    private func setVideoStateFrameMode(state: String, mode: String) {
        guard let selectedID, let current = project.root.find(id: selectedID), current.syncWithState == true else { return }
        project.root.update(id: selectedID) { video in
            var modes = video.syncStateFrameMode ?? ["Locked": "beginning", "Unlock": "end", "Sleep": "beginning"]
            modes[state] = mode
            video.syncStateFrameMode = modes
        }
        applyVideoFrameOverrides(children: current.children, state: state, mode: mode)
    }

    private func removeVideoFrameOverrides(targetIDs: Set<UUID>) {
        guard !targetIDs.isEmpty else { return }
        var all = project.stateOverrides
        for state in Array(all.keys) {
            all[state]?.removeAll { targetIDs.contains($0.targetID) && $0.keyPath == "zPosition" }
        }
        project.stateOverrides = all
    }

    private func applyVideoFrameOverrides(children: [LayerModel], modes: [String: String]) {
        for state in ["Locked", "Unlock", "Sleep"] {
            let fallback = state == "Unlock" ? "end" : "beginning"
            applyVideoFrameOverrides(children: children, state: state, mode: modes[state] ?? fallback)
        }
    }

    private func applyVideoFrameOverrides(children: [LayerModel], state: String, mode: String) {
        let ids = Set(children.map(\.id))
        var all = project.stateOverrides
        var values = all[state] ?? []
        values.removeAll { ids.contains($0.targetID) && $0.keyPath == "zPosition" }
        let count = children.count
        for (index, child) in children.enumerated() {
            let z = mode == "end" ? videoFinalZ(index, count: count) : videoInitialZ(index)
            values.append(.init(targetID: child.id, keyPath: "zPosition", value: .number(z)))
        }
        all[state] = values
        project.stateOverrides = all
    }

    private func videoInitialZ(_ index: Int) -> Double {
        -Double(index * (index + 1)) / 2
    }

    private func videoFinalZ(_ index: Int, count: Int) -> Double {
        Double(index * (2 * count - 1 - index)) / 2
    }

    @ViewBuilder private func animations'''

s2, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'video replacement count={count}')
path.write_text(s2)
Path('.github/video_inspector_patch.py').unlink()
Path('.github/workflows/video-inspector-parity.yml').unlink()
