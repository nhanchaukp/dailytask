import SwiftUI
import Observation
import AppKit

struct ContentView: View {
    @Environment(TaskStore.self) private var store
    @State private var updateChecker = UpdateChecker.shared
    
    @State private var newTaskTitle: String = ""
    @State private var newTaskTags: String = ""
    @State private var selectedDate: Date = Date()
    @State private var showDatePicker: Bool = false
    
    var body: some View {
        @Bindable var store = store
        
        VStack(spacing: 0) {
            if let release = updateChecker.latestRelease, !updateChecker.isDismissed {
                updateBanner(release: release)
            }
            
            headerView(store: store)
            
            taskListView
            
            Divider()
                .opacity(0.35)
            
            footerView
        }
        .frame(width: 380, height: 520)
        .modifier(NativeGlassBackgroundModifier())
        .background(WindowTransparencyConfigurator())
    }
    
    // MARK: - Update Banner (Top Docked, Compact & Dismissible)
    @ViewBuilder
    private func updateBanner(release: ReleaseInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundColor(.accentColor)
                .font(.system(size: 11, weight: .semibold))
            
            Text("Đã có bản cập nhật \(Text("v\(release.version)").fontWeight(.bold).foregroundColor(.primary))")
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.85))
            
            Spacer()
            
            Button("Cập nhật") {
                updateChecker.openReleaseDownload(release)
            }
            .modifier(NativeGlassProminentButtonModifier())
            .controlSize(.mini)
            
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    updateChecker.dismissUpdate()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(3.5)
            }
            .modifier(NativeGlassButtonModifier(shape: Circle()))
            .help("Bỏ qua")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.12))
        .overlay(Divider().opacity(0.35), alignment: .bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    // MARK: - Header View
    @ViewBuilder
    private func headerView(store: TaskStore) -> some View {
        @Bindable var bindableStore = store
        @Bindable var bindableChecker = updateChecker
        
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                    
                    Text("Daily Task")
                        .font(.system(size: 14, weight: .bold))
                }
                
                Spacer()
                
                if store.isSyncing {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                let remaining = store.incompleteTaskCount
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.filterOnlyIncomplete.toggle()
                    }
                } label: {
                    HStack(spacing: 3.5) {
                        if store.filterOnlyIncomplete {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .font(.system(size: 9))
                        }
                        Text("\(remaining) chưa xong")
                            .font(.system(size: 11, weight: store.filterOnlyIncomplete ? .semibold : .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundColor(store.filterOnlyIncomplete ? .white : .secondary)
                    .modifier(NativeGlassTagModifier(isSelected: store.filterOnlyIncomplete))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(store.filterOnlyIncomplete ? "Đang lọc task chưa xong (nhấn để hiện tất cả)" : "Nhấn để chỉ hiện các task chưa xong")
                
                Menu {
                    Toggle("Tự sắp xếp khi hoàn tất", isOn: $bindableStore.autoReorderCompleted)
                    
                    Divider()
                    
                    Button {
                        store.exportToExcel()
                    } label: {
                        Label("Xuất dữ liệu ra Excel (CSV)", systemImage: "tablecells")
                    }
                    
                    Button {
                        store.syncNow()
                    } label: {
                        Label("Đồng bộ iCloud ngay", systemImage: "arrow.triangle.2.circlepath.icloud")
                    }
                    
                    Button(role: .destructive) {
                        store.clearCompletedTasks()
                    } label: {
                        Label("Xoá các task đã xong", systemImage: "trash")
                    }
                    
                    Divider()
                    
                    Toggle("Tự động kiểm tra bản cập nhật", isOn: $bindableChecker.automaticallyCheckForUpdates)
                    
                    Button {
                        Task {
                            await updateChecker.checkForUpdates(isUserInitiated: true)
                        }
                    } label: {
                        if updateChecker.status == .checking {
                            Label("Đang kiểm tra cập nhật...", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Kiểm tra bản cập nhật...", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(updateChecker.status == .checking)
                    
                    Divider()
                    
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Thoát ứng dụng", systemImage: "power")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            // Search Bar (Native liquid glass input with smooth rounded pill corners)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField("Tìm kiếm theo tên task hoặc tag...", text: $bindableStore.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .modifier(NativeGlassInputModifier(cornerRadius: 16))
            
            // Quick Tag Filter Bar if tags exist
            if !store.allAvailableTags.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            Button {
                                store.selectedTagFilter = nil
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: store.selectedTagFilter == nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                        .font(.system(size: 9))
                                    Text("Tất cả")
                                }
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .foregroundColor(store.selectedTagFilter == nil ? .white : .secondary)
                                .modifier(NativeGlassTagModifier(isSelected: store.selectedTagFilter == nil))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            
                            ForEach(store.allAvailableTags, id: \.self) { tag in
                                Button {
                                    if store.selectedTagFilter == tag {
                                        store.selectedTagFilter = nil
                                    } else {
                                        store.selectedTagFilter = tag
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: store.selectedTagFilter == tag ? "tag.fill" : "tag")
                                            .font(.system(size: 9))
                                        Text(tag)
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .foregroundColor(store.selectedTagFilter == tag ? .white : .secondary)
                                    .modifier(NativeGlassTagModifier(isSelected: store.selectedTagFilter == tag))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
    
    // MARK: - Task List View Grouped by Date
    private var taskListView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if store.groupedTasks.isEmpty {
                    Divider().opacity(0.35)
                    emptyStateView
                } else {
                    ForEach(store.groupedTasks) { group in
                        Section {
                            VStack(spacing: 2) {
                                ForEach(group.tasks) { task in
                                    TaskRowView(task: task)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 4)
                            .padding(.bottom, 6)
                        } header: {
                            sectionHeader(title: group.title, count: group.tasks.count, date: group.date)
                        }
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.automatic)
        .controlSize(.small)
    }
    
    // MARK: - Translucent Frosted Date Section Header
    private func sectionHeader(title: String, count: Int, date: Date) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.primary.opacity(0.85))
                .tracking(0.3)
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4.5)
        .background(.ultraThinMaterial)
        .overlay(Divider().opacity(0.3), alignment: .top)
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            
            if !store.searchText.isEmpty || store.selectedTagFilter != nil || store.filterOnlyIncomplete {
                Text("Không tìm thấy task nào phù hợp")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                Text("Chưa có task nào")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Thêm task mới ở khung bên dưới")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
    
    // MARK: - Footer View (Quick Add with Translucent Backdrop)
    private var footerView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("Nhập tên task mới...", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6.5)
                    .modifier(NativeGlassInputModifier(cornerRadius: 16))
                    .onSubmit {
                        submitNewTask()
                    }
                
                Button {
                    submitNewTask()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary.opacity(0.4) : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Thêm task")
            }
            
            HStack(spacing: 8) {
                // Tags Input (Clean, zero background per user request)
                HStack(spacing: 5) {
                    Image(systemName: "tag")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                    
                    ZStack(alignment: .leading) {
                        if newTaskTags.isEmpty {
                            Text("Tags (vd: việc nhà, họp)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.65))
                                .allowsHitTesting(false)
                        }
                        
                        TextField("", text: $newTaskTags)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }
                .frame(height: 24)
                .padding(.horizontal, 4)
                
                Spacer()
                
                // Date Selection - Standard, larger and comfortable size
                DatePicker(
                    "",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.025))
    }
    
    private func submitNewTask() {
        let trimmedTitle = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        let tags = newTaskTags
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        store.addTask(
            title: trimmedTitle,
            tags: tags,
            dueDate: selectedDate
        )
        
        newTaskTitle = ""
        newTaskTags = ""
    }
}

// MARK: - Task Row Component (Clean, Zero Default Background)
struct TaskRowView: View {
    @Environment(TaskStore.self) private var store
    let task: TaskItem
    @State private var isHovering: Bool = false
    @State private var isDeleteHovering: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    store.toggleTask(id: task.id)
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(task.isCompleted ? .accentColor : .secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                // Task Content Highlighted (Stable geometry, no font/width shift)
                Text(task.title)
                    .font(.system(size: 12.5, weight: task.isCompleted ? .regular : .semibold))
                    .strikethrough(task.isCompleted, color: .secondary.opacity(0.6))
                    .foregroundColor(task.isCompleted ? .secondary.opacity(0.7) : .primary)
                    .lineLimit(2)
                
                // Subdued / Muted Tags (Smooth rounded pill chips)
                if !task.tags.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(task.tags, id: \.self) { tag in
                            HStack(spacing: 2.5) {
                                Image(systemName: "tag")
                                    .font(.system(size: 7))
                                Text(tag)
                                    .font(.system(size: 9))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            
            Spacer()
            
            // Delete button: Kept in layout to avoid row width reflow, smooth opacity transition
            Button(role: .destructive) {
                withAnimation {
                    store.deleteTask(id: task.id)
                }
            } label: {
                Image(systemName: isDeleteHovering ? "trash.fill" : "trash")
                    .font(.system(size: 11))
                    .foregroundColor(isDeleteHovering ? .red : .red.opacity(0.75))
                    .padding(4)
                    .background(
                        Circle()
                            .fill(isDeleteHovering ? Color.red.opacity(0.18) : Color.clear)
                    )
                    .scaleEffect(isDeleteHovering ? 1.15 : 1.0)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1.0 : 0.0)
            .disabled(!isHovering)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isDeleteHovering = hovering
                }
            }
            .help("Xoá task")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation(.snappy(duration: 0.15)) {
                store.toggleTask(id: task.id)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
                if !hovering {
                    isDeleteHovering = false
                }
            }
        }
    }
}

// MARK: - Native Liquid Glass & Material Modifiers

/// Full-view glass background (pinned to Rectangle to avoid capsule/oval clipping)
private struct NativeGlassBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: Rectangle())
        } else {
            content
                .background(.ultraThinMaterial)
        }
    }
}

/// Liquid Glass modifier for input text fields (Search, New Task) with smooth pill radius
private struct NativeGlassInputModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                )
        }
    }
}

/// Liquid Glass prominent button style modifier (Update button)
private struct NativeGlassProminentButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
        } else {
            content
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Liquid Glass standard button style modifier
private struct NativeGlassButtonModifier<S: Shape>: ViewModifier {
    var shape: S
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glass)
        } else {
            content
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.06))
                .clipShape(shape)
        }
    }
}

/// Liquid Glass pill filter modifier (Tags)
private struct NativeGlassTagModifier: ViewModifier {
    var isSelected: Bool
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(isSelected ? .regular.tint(Color.accentColor) : .clear, in: Capsule())
        } else {
            content
                .background(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                .clipShape(Capsule())
        }
    }
}

/// Helper that configures the hosting window transparent and non-opaque,
/// enabling true behind-window blur and native glass refraction
private struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}
