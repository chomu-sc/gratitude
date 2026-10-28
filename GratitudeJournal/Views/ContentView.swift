import SwiftUI
import SwiftData

/// 메인 화면: 월간 캘린더 + 선택한 날의 감사일기
/// iPhone은 위아래로, iPad·Mac은 좌우로 배치합니다.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @Query(sort: \GratitudeEntry.createdAt) private var entries: [GratitudeEntry]

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var month = MonthCalendarView.startOfMonth(.now)
    @State private var composeTarget: ComposeTarget?
    @State private var showSyncSettings = false

    private struct ComposeTarget: Identifiable {
        let day: Date
        var id: Date { day }
    }

    private var isWide: Bool {
        #if os(macOS)
        return true
        #else
        return sizeClass == .regular
        #endif
    }

    var body: some View {
        let byDay = Dictionary(grouping: entries) { $0.day }
        let moods = byDay.compactMapValues { $0.first?.recordedEmotion }
        let recordedDays = Set(byDay.keys)

        NavigationStack {
            Group {
                if isWide {
                    HStack(alignment: .top, spacing: 28) {
                        ScrollView { calendar(moods, recordedDays) }
                            .frame(width: 380)
                        ScrollView { detail(byDay) }
                    }
                    .padding(28)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            calendar(moods, recordedDays)
                            detail(byDay)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("감사일기")
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { CloudSyncService.shared.syncNow() }   // 앱을 열 때마다 서버 확인
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSyncSettings = true } label: {
                        Label("동기화 설정", systemImage: "gearshape")
                    }
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        composeTarget = ComposeTarget(day: Calendar.current.startOfDay(for: .now))
                    } label: {
                        Label("오늘의 감사일기 쓰기", systemImage: "square.and.pencil")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) { SyncStatusView() }
                #else
                ToolbarItem(placement: .status) { SyncStatusView() }
                #endif
            }
        }
        .sheet(item: $composeTarget) { target in
            NavigationStack {
                GratitudeFlowView(day: target.day) { savedDay in
                    composeTarget = nil
                    if let savedDay { select(savedDay) }
                }
                .navigationTitle("감사일기 쓰기")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { composeTarget = nil }
                    }
                }
            }
            #if os(macOS)
            .frame(width: 520, height: 620)
            #endif
        }
        .sheet(isPresented: $showSyncSettings) {
            NavigationStack {
                SyncSettingsView()
                    .navigationTitle("동기화")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("완료") { showSyncSettings = false }
                        }
                    }
            }
        }
    }

    private func calendar(_ moods: [Date: EmotionLevel], _ recordedDays: Set<Date>) -> some View {
        MonthCalendarView(
            month: $month,
            selection: Binding(get: { selectedDay }, set: { select($0) }),
            moods: moods,
            recordedDays: recordedDays
        )
    }

    private func detail(_ byDay: [Date: [GratitudeEntry]]) -> some View {
        DayDetailView(
            day: selectedDay,
            entries: byDay[selectedDay] ?? [],
            onWrite: { composeTarget = ComposeTarget(day: selectedDay) },
            onDelete: { try? EntryRepository(context: context).deleteEntries(on: selectedDay) }
        )
    }

    private func select(_ day: Date) {
        selectedDay = Calendar.current.startOfDay(for: day)
        withAnimation(.snappy) { month = MonthCalendarView.startOfMonth(day) }
    }
}

// MARK: - 월간 캘린더

/// 기록한 날은 그날 기분 색으로 칠해지는 달력. 좌우 스와이프 또는 ‹ › 로 달 이동.
struct MonthCalendarView: View {
    @Binding var month: Date
    @Binding var selection: Date
    /// 날짜(00:00) → 그날 기분
    let moods: [Date: EmotionLevel]
    /// 기록이 있는 날짜 (기분 미기록 포함)
    let recordedDays: Set<Date>

    private var cal: Calendar { .current }

    static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? cal.startOfDay(for: date)
    }

    private var isCurrentMonth: Bool { cal.isDate(month, equalTo: .now, toGranularity: .month) }

    /// 첫 요일 설정(일요일/월요일 시작)을 반영한 요일 머리글
    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// nil = 앞쪽 빈 칸
    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let days = range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: month) }
        let blanks: [Date?] = Array(repeating: nil, count: leading)
        return blanks + days.map { Optional($0) }
    }

    var body: some View {
        VStack(spacing: 14) {
            header

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(weekdayColor(column: index))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
            .id(month)
            .transition(.opacity)

            footer
        }
        .padding(16)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -60 { moveMonth(1) }
                else if value.translation.width > 60 { moveMonth(-1) }
            }
        )
    }

    private var header: some View {
        HStack {
            Text(month, format: .dateTime.year().month(.wide))
                .font(.title3.bold())
            Spacer()
            if !isCurrentMonth {
                Button("오늘") { selection = .now }
                    .font(.subheadline)
            }
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 28, height: 28)
            }
            .help("이전 달")
            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 28, height: 28)
            }
            .disabled(isCurrentMonth)
            .help("다음 달")
        }
        .buttonStyle(.borderless)
    }

    private func dayCell(_ date: Date) -> some View {
        let mood = moods[date]
        let hasRecord = recordedDays.contains(date)
        let isSelected = cal.isDate(date, inSameDayAs: selection)
        let isToday = cal.isDateInToday(date)
        let isFuture = date > .now

        return Button { selection = date } label: {
            ZStack {
                // 기분 색으로 칠함. 기록은 있는데 기분 미기록이면 회색.
                Circle().fill(mood?.color ?? (hasRecord ? Color.secondary.opacity(0.25) : Color.clear))
                if isSelected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 2)
                        .padding(-3)
                }
                Text("\(cal.component(.day, from: date))")
                    .font(.callout.weight(isToday ? .heavy : .medium).monospacedDigit())
                    .foregroundStyle(
                        mood != nil ? Color.black.opacity(0.75)
                        : isFuture ? Color.secondary.opacity(0.4)
                        : Color.primary
                    )
                if isToday && !hasRecord {
                    Circle().fill(Color.gratitudeYellow).frame(width: 5, height: 5).offset(y: 12)
                }
            }
            .frame(width: 36, height: 36)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(Text(date, format: .dateTime.month().day()))
        .accessibilityValue(mood.map { "기록 있음, \($0.label)" } ?? (hasRecord ? "기록 있음, 기분 미기록" : "기록 없음"))
    }

    // MARK: 이 달의 감정 분포

    private var footer: some View {
        let inMonth: (Date) -> Bool = { cal.isDate($0, equalTo: month, toGranularity: .month) }
        let totalDays = recordedDays.filter(inMonth).count
        var counts: [EmotionLevel: Int] = [:]
        for (day, level) in moods where inMonth(day) {
            counts[level, default: 0] += 1
        }
        let unsetDays = totalDays - counts.values.reduce(0, +)

        return VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text("이 달의 감정").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(totalDays)일 기록")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if totalDays == 0 {
                Text("이 달에는 아직 기록이 없어요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 7) {
                    // 기분 좋은 순으로 7단계 모두 표시 (0일인 단계는 흐리게)
                    ForEach(EmotionLevel.allCases.reversed()) { level in
                        distributionRow(
                            icon: AnyView(MoodFace(level: level).frame(width: 16)),
                            label: level.label,
                            color: level.color,
                            count: counts[level, default: 0],
                            total: totalDays
                        )
                    }
                    if unsetDays > 0 {
                        distributionRow(
                            icon: AnyView(Image(systemName: "face.dashed").font(.caption).foregroundStyle(.secondary).frame(width: 16)),
                            label: "기분 미기록",
                            color: Color.secondary.opacity(0.5),
                            count: unsetDays,
                            total: totalDays
                        )
                    }
                }
            }
        }
    }

    private func distributionRow(icon: AnyView, label: String, color: Color, count: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            icon
            Text(label)
                .font(.caption)
                .frame(width: 84, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    if count > 0 {
                        Capsule()
                            .fill(color)
                            .frame(width: max(6, geo.size.width * CGFloat(count) / CGFloat(max(total, 1))))
                    }
                }
            }
            .frame(height: 8)
            Text("\(count)일")
                .font(.caption.monospacedDigit())
                .foregroundStyle(count > 0 ? Color.primary : Color.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .opacity(count > 0 ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(count)일")
    }

    /// 일요일 빨강, 토요일 파랑
    private func weekdayColor(column: Int) -> Color {
        let weekday = (column + cal.firstWeekday - 1) % 7 + 1
        switch weekday {
        case 1:  return .red.opacity(0.8)
        case 7:  return .blue.opacity(0.8)
        default: return .secondary
        }
    }

    private func moveMonth(_ value: Int) {
        guard let moved = cal.date(byAdding: .month, value: value, to: month),
              moved <= Self.startOfMonth(.now) else { return }
        withAnimation(.snappy) { month = moved }
    }
}

// MARK: - 선택한 날의 기록

struct DayDetailView: View {
    let day: Date
    let entries: [GratitudeEntry]
    let onWrite: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false

    private var items: [String] { entries.flatMap { $0.items } }
    private var isFuture: Bool { day > .now }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(day, format: .dateTime.year().month(.wide).day().weekday(.wide))
                .font(.title3.bold())

            if let entry = entries.first {
                filled(entry)
            } else {
                empty
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .confirmationDialog("이 날의 감사일기를 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive, action: onDelete)
        } message: {
            Text("삭제하면 되돌릴 수 없어요.")
        }
    }

    private func filled(_ entry: GratitudeEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                if let mood = entry.recordedEmotion {
                    MoodFace(level: mood).frame(width: 48)
                } else {
                    Image(systemName: "face.dashed")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                        .frame(width: 48)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.recordedEmotion?.label ?? "기분 미기록").font(.headline)
                    if entry.recordedEmotion == nil {
                        Text("[수정 · 더 적기]에서 그날의 기분을 남길 수 있어요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let summary = entry.summary {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("감사한 일 \(items.count)가지")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        NumberBadge(number: index + 1)
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }

            HStack {
                Button(action: onWrite) {
                    Label("수정 · 더 적기", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("삭제", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isFuture ? "아직 오지 않은 날이에요." : "이 날의 감사일기가 없어요.")
                .foregroundStyle(.secondary)
            if !isFuture {
                Button(action: onWrite) {
                    Label(Calendar.current.isDateInToday(day) ? "오늘의 감사일기 쓰기" : "이 날 감사일기 쓰기",
                          systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    ContentView().modelContainer(AppContainer.preview)
}
