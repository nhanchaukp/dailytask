import Foundation
import SwiftUI
import Observation
import AppKit
import UniformTypeIdentifiers

@Observable
final class TaskStore {
    var tasks: [TaskItem] = [] {
        didSet {
            if !isApplyingCloudUpdate {
                saveTasks()
            }
        }
    }
    var searchText: String = ""
    var selectedTagFilter: String? = nil
    var filterOnlyIncomplete: Bool = false
    var lastSyncDate: Date? = nil
    var isSyncing: Bool = false
    var autoReorderCompleted: Bool = false {
        didSet {
            UserDefaults.standard.set(autoReorderCompleted, forKey: autoReorderKey)
        }
    }

    @ObservationIgnored
    private let storageKey = "daily_tasks_data_v1"
    @ObservationIgnored
    private let deletedIdsKey = "daily_tasks_deleted_ids_v1"
    @ObservationIgnored
    private let autoReorderKey = "daily_tasks_auto_reorder_completed_v1"
    @ObservationIgnored
    private var deletedTaskIds: Set<UUID> = []
    @ObservationIgnored
    private var isApplyingCloudUpdate: Bool = false
    @ObservationIgnored
    private var cloudSyncTask: Task<Void, Never>? = nil

    init() {
        autoReorderCompleted = UserDefaults.standard.bool(forKey: autoReorderKey)
        loadDeletedIds()
        loadLocalTasks()
        if tasks.isEmpty {
            loadSampleTasks()
        }
        
        // Initial iCloud sync
        syncWithCloud()
        
        // Start observing external changes from iCloud
        startCloudObserver()
    }

    deinit {
        cloudSyncTask?.cancel()
    }

    // MARK: - Filter & Computed Properties
    var incompleteTaskCount: Int {
        tasks.filter { !$0.isCompleted }.count
    }

    var allAvailableTags: [String] {
        let all = tasks.flatMap { $0.tags }
        return Array(Set(all)).sorted()
    }

    var filteredTasks: [TaskItem] {
        var result = tasks
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if filterOnlyIncomplete {
            result = result.filter { !$0.isCompleted }
        }

        if !trimmedSearch.isEmpty {
            result = result.filter { task in
                task.title.localizedCaseInsensitiveContains(trimmedSearch) ||
                task.tags.contains { $0.localizedCaseInsensitiveContains(trimmedSearch) }
            }
        }

        if let tagFilter = selectedTagFilter, !tagFilter.isEmpty {
            result = result.filter { $0.tags.contains(where: { $0.caseInsensitiveCompare(tagFilter) == .orderedSame }) }
        }

        return result
    }

    struct TaskDateGroup: Identifiable {
        var id: Date
        var date: Date
        var title: String
        var tasks: [TaskItem]
    }

    var groupedTasks: [TaskDateGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let groupedDict = Dictionary(grouping: filteredTasks) { task in
            calendar.startOfDay(for: task.dueDate)
        }

        // Always keep "Hôm nay" at the very top, followed by upcoming dates, then past dates
        let sortedDates = groupedDict.keys.sorted { d1, d2 in
            if d1 == today { return true }
            if d2 == today { return false }

            let isD1Future = d1 > today
            let isD2Future = d2 > today

            if isD1Future && !isD2Future {
                return true
            } else if !isD1Future && isD2Future {
                return false
            } else if isD1Future && isD2Future {
                return d1 < d2
            } else {
                return d1 > d2
            }
        }

        return sortedDates.map { dayDate in
            let dayTasks = groupedDict[dayDate]?.sorted(by: {
                if autoReorderCompleted {
                    if $0.isCompleted != $1.isCompleted {
                        return !$0.isCompleted
                    }
                }
                return $0.createdAt < $1.createdAt
            }) ?? []

            return TaskDateGroup(
                id: dayDate,
                date: dayDate,
                title: formattedDateTitle(for: dayDate, calendar: calendar),
                tasks: dayTasks
            )
        }
    }

    private func formattedDateTitle(for date: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: Date())
        let dayDifference = calendar.dateComponents([.day], from: today, to: date).day ?? 0

        switch dayDifference {
        case 0:
            return "Hôm nay"
        case 1:
            return "Ngày mai"
        case -1:
            return "Hôm qua"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "EEEE, dd/MM/yyyy"
            return formatter.string(from: date).capitalized
        }
    }

    // MARK: - Task Mutations (Fast, Non-blocking)
    func addTask(title: String, tags: [String] = [], dueDate: Date = Date()) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let cleanTags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let now = Date()
        let newTask = TaskItem(
            title: trimmedTitle,
            isCompleted: false,
            dueDate: dueDate,
            tags: cleanTags,
            createdAt: now,
            updatedAt: now
        )
        tasks.append(newTask)
    }

    func toggleTask(id: UUID) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].isCompleted.toggle()
            tasks[index].updatedAt = Date()
        }
    }

    func deleteTask(id: UUID) {
        deletedTaskIds.insert(id)
        tasks.removeAll { $0.id == id }
        saveDeletedIds()
    }

    func clearCompletedTasks() {
        let completedIds = tasks.filter { $0.isCompleted }.map { $0.id }
        deletedTaskIds.formUnion(completedIds)
        tasks.removeAll { $0.isCompleted }
        saveDeletedIds()
    }

    // MARK: - Export to Excel (CSV with UTF-8 BOM, Non-blocking SavePanel)
    @MainActor
    func exportToExcel() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let timestamp = formatter.string(from: Date())
        savePanel.nameFieldStringValue = "DailyTasks_\(timestamp).csv"
        savePanel.title = "Xuất danh sách task ra Excel"
        savePanel.prompt = "Xuất file"
        savePanel.message = "File định dạng CSV tương thích hoàn toàn với Microsoft Excel, Apple Numbers và Google Sheets."

        NSApp.activate(ignoringOtherApps: true)

        savePanel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = savePanel.url else { return }
            let csvContent = self.generateCSV()
            do {
                try csvContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Lỗi xuất file Excel: \(error)")
            }
        }
    }

    private func generateCSV() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "dd/MM/yyyy HH:mm"

        // \u{FEFF} is UTF-8 Byte Order Mark (BOM), ensuring Excel displays Vietnamese accented characters properly
        var csvString = "\u{FEFF}"
        csvString.append("STT,Tên công việc,Trạng thái,Ngày thực hiện,Thẻ (Tags),Ngày tạo\n")

        for (index, task) in tasks.enumerated() {
            let stt = "\(index + 1)"
            let title = escapeCSV(task.title)
            let status = task.isCompleted ? "Đã hoàn thành" : "Chưa hoàn thành"
            let dueDate = escapeCSV(dateFormatter.string(from: task.dueDate))
            let tags = escapeCSV(task.tags.joined(separator: ", "))
            let createdAt = escapeCSV(dateTimeFormatter.string(from: task.createdAt))

            csvString.append("\(stt),\(title),\(status),\(dueDate),\(tags),\(createdAt)\n")
        }

        return csvString
    }

    private func escapeCSV(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return text
    }

    // MARK: - iCloud & Persistence
    func syncNow() {
        syncWithCloud()
    }

    private func startCloudObserver() {
        cloudSyncTask?.cancel()
        cloudSyncTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification) {
                guard let self = self else { return }
                self.handleCloudChangeNotification(notification)
            }
        }
    }

    @MainActor
    private func handleCloudChangeNotification(_ notification: Notification) {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        guard let userInfo = notification.userInfo,
              let reasonNumber = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber else {
            mergeWithCloudData()
            return
        }

        let reason = reasonNumber.intValue
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            mergeWithCloudData()
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            print("Warning: iCloud Key-Value Store quota exceeded.")
        case NSUbiquitousKeyValueStoreAccountChange:
            mergeWithCloudData()
        default:
            mergeWithCloudData()
        }
    }

    private func syncWithCloud() {
        isSyncing = true
        NSUbiquitousKeyValueStore.default.synchronize()
        mergeWithCloudData()
        isSyncing = false
        lastSyncDate = Date()
    }

    private func mergeWithCloudData() {
        let cloudStore = NSUbiquitousKeyValueStore.default
        
        // 1. Merge deleted task IDs
        if let cloudDeletedArray = cloudStore.array(forKey: deletedIdsKey) as? [String] {
            let cloudDeletedUUIDs = Set(cloudDeletedArray.compactMap { UUID(uuidString: $0) })
            deletedTaskIds.formUnion(cloudDeletedUUIDs)
            saveDeletedIds()
        }

        // 2. Decode cloud tasks
        var cloudTasks: [TaskItem] = []
        if let cloudData = cloudStore.data(forKey: storageKey) {
            do {
                cloudTasks = try JSONDecoder().decode([TaskItem].self, from: cloudData)
            } catch {
                print("Failed to decode cloud tasks: \(error)")
            }
        }

        // 3. Smart Merge with local tasks
        var mergedDict: [UUID: TaskItem] = [:]

        // Add local tasks that are not marked deleted
        for localTask in tasks where !deletedTaskIds.contains(localTask.id) {
            mergedDict[localTask.id] = localTask
        }

        // Merge cloud tasks
        for cloudTask in cloudTasks where !deletedTaskIds.contains(cloudTask.id) {
            if let existing = mergedDict[cloudTask.id] {
                // Keep the version with the newer updatedAt date
                if cloudTask.updatedAt > existing.updatedAt {
                    mergedDict[cloudTask.id] = cloudTask
                }
            } else {
                mergedDict[cloudTask.id] = cloudTask
            }
        }

        let updatedTasks = Array(mergedDict.values)

        isApplyingCloudUpdate = true
        tasks = updatedTasks
        isApplyingCloudUpdate = false

        // Save consolidated state back to local and cloud
        saveTasks()
    }

    private func saveTasks() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        
        // 1. Fast local cache save (non-blocking)
        UserDefaults.standard.set(data, forKey: storageKey)
        
        // 2. Push to iCloud Key-Value Store asynchronously without blocking Main Thread
        let key = storageKey
        DispatchQueue.global(qos: .utility).async {
            let cloudStore = NSUbiquitousKeyValueStore.default
            cloudStore.set(data, forKey: key)
        }
    }

    private func loadLocalTasks() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            tasks = try JSONDecoder().decode([TaskItem].self, from: data)
        } catch {
            print("Failed to load local tasks: \(error)")
        }
    }

    private func saveDeletedIds() {
        let array = Array(deletedTaskIds.suffix(300)).map { $0.uuidString }
        UserDefaults.standard.set(array, forKey: deletedIdsKey)
        
        let key = deletedIdsKey
        DispatchQueue.global(qos: .utility).async {
            let cloudStore = NSUbiquitousKeyValueStore.default
            cloudStore.set(array, forKey: key)
        }
    }

    private func loadDeletedIds() {
        if let localArray = UserDefaults.standard.stringArray(forKey: deletedIdsKey) {
            deletedTaskIds = Set(localArray.compactMap { UUID(uuidString: $0) })
        }
    }

    private func loadSampleTasks() {
        let calendar = Calendar.current
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let now = Date()
        tasks = [
            TaskItem(title: "Họp standup hàng ngày", isCompleted: true, dueDate: today, tags: ["Công việc", "Họp"], createdAt: now, updatedAt: now),
            TaskItem(title: "Review pull request Daily Task", isCompleted: false, dueDate: today, tags: ["Code"], createdAt: now, updatedAt: now),
            TaskItem(title: "Chuẩn bị tài liệu báo cáo tuần", isCompleted: false, dueDate: tomorrow, tags: ["Báo cáo"], createdAt: now, updatedAt: now),
            TaskItem(title: "Cập nhật ứng dụng lên bản mới nhất", isCompleted: true, dueDate: yesterday, tags: ["Hệ thống"], createdAt: now, updatedAt: now)
        ]
    }
}
