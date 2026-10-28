import SwiftUI
import SwiftData

extension Color {
    /// 앱 아이콘과 같은 노란색
    static let gratitudeYellow = Color(red: 1.0, green: 0.82, blue: 0.28)
}

/// 감사일기 작성 흐름
///
///  ① 감사한 일을 하나 적고 → [더 적기] 또는 [그만 적기]
///  ② [그만 적기] → 오늘의 기분 + 한 줄 총평 → [저장]
///
/// 상단 날짜 바에서 언제든 날짜를 바꿀 수 있고, 그 날짜에 이미 기록이 있으면 이어서 씁니다.
/// 메인 앱(시트), macOS 빠른 작성 패널, 메뉴 막대에서 공용으로 씁니다.
///
/// 자동 저장: 닫기(시트 닫기·스와이프), 패널 숨김, 앱이 백그라운드로 갈 때 그때까지 적은 내용을 저장합니다.
/// 기분 화면까지 가지 않았다면 '기분 미기록'으로 저장되고, 나중에 [수정 · 더 적기]에서 채울 수 있습니다.
struct GratitudeFlowView: View {
    enum Style { case regular, compact }
    private enum Step { case items, wrapUp, done }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    let style: Style
    /// 저장하면 저장된 날짜, 그 외엔 nil
    let onFinish: (Date?) -> Void

    @State private var draft: EntryDraft
    @State private var current = ""
    @State private var step: Step = .items
    @State private var didLoad = false
    @State private var saveError: String?
    @FocusState private var inputFocused: Bool

    static let summaryLimit = 80

    init(day: Date = .now, style: Style = .regular, onFinish: @escaping (Date?) -> Void) {
        self.style = style
        self.onFinish = onFinish
        _draft = State(initialValue: EntryDraft(day: day))
    }

    private var isCompact: Bool { style == .compact }
    private var isToday: Bool { Calendar.current.isDateInToday(draft.day) }
    private var trimmedCurrent: String { current.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canFinishItems: Bool { !trimmedCurrent.isEmpty || draft.canSave }

    var body: some View {
        VStack(spacing: 0) {
            if step != .done {
                DayPickerBar(
                    day: Binding(get: { draft.day }, set: { changeDay(to: $0) }),
                    usesPopover: !isCompact
                )
                .padding(.horizontal, isCompact ? 12 : 20)
                .padding(.vertical, isCompact ? 8 : 12)
                Divider()
            }

            Group {
                switch step {
                case .items:  itemsStep.transition(slide)
                case .wrapUp: wrapUpStep.transition(slide)
                case .done:   doneStep.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.snappy(duration: 0.3), value: step)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            changeDay(to: draft.day)
            focusInput()
        }
        .onDisappear(perform: autosave)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { autosave() }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .quickEntryDidHide)) { _ in
            if isCompact { autosave() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickEntryDidShow)) { _ in
            guard isCompact else { return }
            // 쓰다 만 내용이 없으면 다시 열 때마다 '오늘'로
            if step == .items, !draft.hasNewItems, current.isEmpty, !isToday {
                changeDay(to: .now)
            }
            focusInput()
        }
        #endif
        .alert("저장하지 못했어요", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var slide: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity))
    }

    // MARK: - ① 감사한 일 하나씩

    private var itemsStep: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: isCompact ? 10 : 14) {
                        Text(isToday ? "오늘 어떤 일이 감사했나요?" : "이 날 어떤 일이 감사했나요?")
                            .font(isCompact ? .headline : .title2.bold())
                        Label(draft.isExistingDay ? "이 날의 기록에 이어서 적어요 · 닫아도 자동 저장돼요"
                                                  : "닫아도 지금까지 적은 내용은 자동 저장돼요",
                              systemImage: draft.isExistingDay ? "text.append" : "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach($draft.items) { $item in
                            writtenRow(number: number(of: item), text: $item.text) { remove(item) }
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        inputRow.id("input")
                    }
                    .padding(isCompact ? 14 : 20)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: draft.items.count) {
                    withAnimation { proxy.scrollTo("input", anchor: .bottom) }
                }
            }

            bottomBar {
                Button(action: finishItems) {
                    Text("그만 적기").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canFinishItems)
                .keyboardShortcut(.return, modifiers: .command)
                .help("⌘↩")

                Button(action: addMore) {
                    Label("더 적기", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedCurrent.isEmpty)
                .help("↩")
            }
        }
    }

    /// 이미 적은 항목 (탭해서 고치기, ⓧ로 지우기)
    private func writtenRow(number: Int, text: Binding<String>, onDelete: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            NumberBadge(number: number)
            TextField("", text: text, axis: .vertical)
                .textFieldStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("이 항목 지우기")
        }
        .padding(12)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 지금 적는 항목
    private var inputRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            NumberBadge(number: draft.items.count + 1, filled: false)
            TextField(draft.items.isEmpty ? "감사한 일 하나를 적어주세요" : "또 감사한 일이 있나요?",
                      text: $current, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit(addMore)
                .onChange(of: current) { _, newValue in
                    // 여러 줄 입력칸에서 Return = '더 적기'
                    if newValue.contains("\n") {
                        current = newValue.replacingOccurrences(of: "\n", with: "")
                        addMore()
                    }
                }
                #if os(iOS)
                .submitLabel(.next)
                #endif
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.gratitudeYellow, lineWidth: 1.5)
        )
    }

    // MARK: - ② 기분 + 한 줄 총평

    private var wrapUpStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: isCompact ? 18 : 28) {
                    Text(isToday ? "오늘 하루는 어땠나요?" : "그날 하루는 어땠나요?")
                        .font(isCompact ? .headline : .title2.bold())

                    EmotionSlider(level: $draft.emotion, compact: isCompact)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("한 줄 총평").font(.headline)
                            Text("선택")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.fill.tertiary, in: Capsule())
                        }
                        TextField("예) 동료의 응원 덕분에 버틸 수 있었던 하루", text: $draft.summary, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...3)
                            .padding(12)
                            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onChange(of: draft.summary) { _, newValue in
                                if newValue.count > Self.summaryLimit {
                                    draft.summary = String(newValue.prefix(Self.summaryLimit))
                                }
                            }
                        Text("\(draft.summary.count)/\(Self.summaryLimit)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("감사한 일 \(draft.cleanedItems.count)가지")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(draft.cleanedItems.enumerated()), id: \.offset) { index, text in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                NumberBadge(number: index + 1)
                                Text(text).lineLimit(2)
                            }
                            .font(.callout)
                        }
                    }
                }
                .padding(isCompact ? 14 : 20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            bottomBar {
                Button {
                    step = .items
                    focusInput()
                } label: {
                    Label("감사한 일", systemImage: "chevron.left").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: save) {
                    Label("저장", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help("⌘↩")
            }
        }
    }

    // MARK: - ③ 완료

    private var doneStep: some View {
        VStack(spacing: 14) {
            MoodFace(level: draft.emotion).frame(width: isCompact ? 72 : 110)
            Text("기록했어요").font(.title2.bold())
            Text("감사한 일 \(draft.cleanedItems.count)가지 · \(draft.emotion.label)")
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Helpers

    private func bottomBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) { content() }
                .controlSize(isCompact ? .regular : .large)
                .padding(.horizontal, isCompact ? 14 : 20)
                .padding(.vertical, isCompact ? 10 : 14)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
        .background(.bar)
    }

    private func number(of item: DraftItem) -> Int {
        (draft.items.firstIndex { $0.id == item.id } ?? 0) + 1
    }

    // MARK: - Actions

    private func addMore() {
        let text = trimmedCurrent
        guard !text.isEmpty else { focusInput(); return }
        withAnimation(.snappy) {
            draft.items.append(DraftItem(text: text, isNew: true))
        }
        current = ""
        focusInput()
    }

    private func finishItems() {
        let text = trimmedCurrent
        if !text.isEmpty {
            draft.items.append(DraftItem(text: text, isNew: true))
            current = ""
        }
        guard draft.canSave else { return }
        inputFocused = false
        draft.emotionChosen = true      // 기분 화면을 봤으면 슬라이더 값(기본 '보통')도 선택으로 간주
        step = .wrapUp
    }

    private func remove(_ item: DraftItem) {
        withAnimation(.snappy) {
            draft.items.removeAll { $0.id == item.id }
        }
    }

    private func changeDay(to day: Date) {
        let existing = (try? EntryRepository(context: context).entries(on: day)) ?? []
        draft.load(day: day, existing: existing)
    }

    private func save() {
        do {
            try EntryRepository(context: context).save(draft)
            draft.markSaved()
            let savedDay = draft.day
            step = .done
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                onFinish(savedDay)
                if isCompact { reset() }      // 패널은 계속 살아있으므로 다음 작성을 위해 초기화
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// 닫거나 숨길 때: 입력칸에 쓰던 것까지 포함해 바뀐 내용이 있으면 조용히 저장
    private func autosave() {
        guard step != .done else { return }
        let text = trimmedCurrent
        if !text.isEmpty {
            draft.items.append(DraftItem(text: text, isNew: true))
            current = ""
        }
        guard draft.hasChanges, draft.canSave else { return }
        do {
            try EntryRepository(context: context).save(draft)
            draft.markSaved()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func reset() {
        draft = EntryDraft(day: .now)
        current = ""
        step = .items
        changeDay(to: .now)
    }

    private func focusInput() {
        Task { inputFocused = true }
    }
}

// MARK: - 날짜 선택 바

/// ‹ 10월 27일 (월) [어제] › — 화살표로 하루씩, 가운데를 누르면 달력에서 고르기. 미래 날짜는 선택 불가.
struct DayPickerBar: View {
    @Binding var day: Date
    /// false면 달력을 팝오버 대신 아래로 펼침 (플로팅 패널·메뉴 막대용)
    var usesPopover = true

    @State private var showCalendar = false
    private var cal: Calendar { .current }
    private var isToday: Bool { cal.isDateInToday(day) }

    private var relativeLabel: String {
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: day), to: cal.startOfDay(for: .now)).day ?? 0
        switch diff {
        case 0:  return "오늘"
        case 1:  return "어제"
        case 2:  return "그저께"
        default: return "\(diff)일 전"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .help("전날")

                Spacer(minLength: 0)

                Button { withAnimation(.snappy) { showCalendar.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar").foregroundStyle(.secondary)
                        Text(day, format: .dateTime.month(.wide).day().weekday(.abbreviated))
                            .font(.headline)
                        Text(relativeLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isToday ? Color.black.opacity(0.75) : Color.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(isToday ? Color.gratitudeYellow : Color.secondary.opacity(0.15), in: Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("날짜 선택, \(relativeLabel)")
                .popover(isPresented: usesPopover ? $showCalendar : .constant(false)) {
                    calendarPicker
                        .padding()
                        .frame(minWidth: 300)
                        .presentationCompactAdaptation(.popover)
                }

                Spacer(minLength: 0)

                Button { shift(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(isToday)
                .help("다음 날")
            }

            if !usesPopover && showCalendar {
                calendarPicker
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var calendarPicker: some View {
        VStack(spacing: 8) {
            DatePicker("날짜",
                       selection: Binding(get: { day }, set: { pick($0) }),
                       in: ...Date.now,
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            if !isToday {
                Button("오늘로 이동") { pick(.now) }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func pick(_ date: Date) {
        day = date
        withAnimation(.snappy) { showCalendar = false }
    }

    private func shift(_ value: Int) {
        guard let moved = cal.date(byAdding: .day, value: value, to: day) else { return }
        day = min(moved, .now)
    }
}

/// 번호 동그라미
struct NumberBadge: View {
    let number: Int
    var filled = true

    var body: some View {
        Text("\(number)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(filled ? Color.black.opacity(0.7) : Color.secondary)
            .frame(width: 22, height: 22)
            .background(Circle().fill(filled ? Color.gratitudeYellow : Color.secondary.opacity(0.15)))
    }
}

#Preview {
    NavigationStack {
        GratitudeFlowView { _ in }
    }
    .modelContainer(AppContainer.preview)
}
