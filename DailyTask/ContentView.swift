import SwiftUI
import Observation

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
            headerView(store: store)
            
            if let release = updateChecker.latestRelease {
                updateBanner(release: release)
            }
            
            taskListView
            
            Divider()
            
            footerView
        }
        .frame(width: 380, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Update Banner
    @ViewBuilder
    private func updateBanner(release: ReleaseInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Đã có bản cập nhật v\(release.version)")
                    .font(.system(size: 11, weight: .bold))
                Text("Bấm để tải về và cập nhật")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Cập nhật") {
                updateChecker.openReleaseDownload(release)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.top, 4)
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
                Text("\(remaining) chưa xong")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.14))
                    .clipShape(Capsule())
                
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
            
            // Search Bar
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
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            
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
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(store.selectedTagFilter == nil ? Color.accentColor : Color.secondary.opacity(0.12))
                                .foregroundColor(store.selectedTagFilter == nil ? .white : .secondary)
                                .cornerRadius(5)
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
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(store.selectedTagFilter == tag ? Color.accentColor : Color.secondary.opacity(0.12))
                                    .foregroundColor(store.selectedTagFilter == tag ? .white : .secondary)
                                    .cornerRadius(5)
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
    
    // MARK: - Task List View Grouped by Date (Compact, Slim Transient Scrollbar)
    private var taskListView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if store.groupedTasks.isEmpty {
                    Divider()
                    emptyStateView
                } else {
                    ForEach(store.groupedTasks) { group in
                        Section {
                            VStack(spacing: 4) {
                                ForEach(group.tasks) { task in
                                    TaskRowView(task: task)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, 8)
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
    
    // MARK: - Darker Date Section Header (Seamlessly Docked)
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
                .background(Color.primary.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4.5)
        .background(
            Color(NSColor.windowBackgroundColor)
                .overlay(Color.primary.opacity(0.08))
        )
        .overlay(Divider(), alignment: .top)
        .overlay(Divider(), alignment: .bottom)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            
            if !store.searchText.isEmpty || store.selectedTagFilter != nil {
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
    
    // MARK: - Footer View (Quick Add)
    private var footerView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("Nhập tên task mới...", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
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
                // Tags Input (Optional) - Fixed placeholder jump with steady ZStack
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
                .padding(.horizontal, 7)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .cornerRadius(6)
                
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
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
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

// MARK: - Task Row Component (Snappy Toggle, Zero Layout Jitter)
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
                
                // Subdued / Muted Tags
                if !task.tags.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(task.tags, id: \.self) { tag in
                            HStack(spacing: 2) {
                                Image(systemName: "tag")
                                    .font(.system(size: 7))
                                Text(tag)
                                    .font(.system(size: 9))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.secondary)
                            .cornerRadius(3)
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
                .fill(isHovering ? Color.primary.opacity(0.06) : Color(NSColor.controlBackgroundColor).opacity(0.45))
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
