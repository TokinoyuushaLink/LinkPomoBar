import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - 极简内置本地化管理
struct Localized {
    // 检测首选语言是否为中文（包括 zh-Hans, zh-Hant, zh-HK 等）
    static var isChinese: Bool {
        if let lang = Locale.preferredLanguages.first {
            return lang.hasPrefix("zh")
        }
        return false
    }
    
    // 根据系统语言返回对应的文本
    static func text(zh: String, en: String) -> String {
        return isChinese ? zh : en
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {

    var statusItem: NSStatusItem!
    var timer: Timer?
    var remainingSeconds = 0
    var isRunning = false
    var isBreak = false

    // MARK: - 持久化配置项
    var workMin: Int {
        get { UserDefaults.standard.integer(forKey: "workMin") == 0 ? 25 : UserDefaults.standard.integer(forKey: "workMin") }
        set { UserDefaults.standard.set(newValue, forKey: "workMin") }
    }
    
    var breakMin: Int {
        get { UserDefaults.standard.integer(forKey: "breakMin") == 0 ? 5 : UserDefaults.standard.integer(forKey: "breakMin") }
        set { UserDefaults.standard.set(newValue, forKey: "breakMin") }
    }
    
    var showSeconds: Bool {
        get {
            if UserDefaults.standard.object(forKey: "showSeconds") == nil { return true }
            return UserDefaults.standard.bool(forKey: "showSeconds")
        }
        set { UserDefaults.standard.set(newValue, forKey: "showSeconds") }
    }
    
    var totalCycles: Int {
        get { UserDefaults.standard.integer(forKey: "totalCycles") == 0 ? 4 : UserDefaults.standard.integer(forKey: "totalCycles") }
        set { UserDefaults.standard.set(newValue, forKey: "totalCycles") }
    }
    
    var currentCyclesLeft: Int {
        get {
            if UserDefaults.standard.object(forKey: "currentCyclesLeft") == nil { return totalCycles }
            return UserDefaults.standard.integer(forKey: "currentCyclesLeft")
        }
        set { UserDefaults.standard.set(newValue, forKey: "currentCyclesLeft") }
    }
    
    var autoAdvance: Bool {
        get {
            if UserDefaults.standard.object(forKey: "autoAdvance") == nil { return true }
            return UserDefaults.standard.bool(forKey: "autoAdvance")
        }
        set { UserDefaults.standard.set(newValue, forKey: "autoAdvance") }
    }

    var toggleItem: NSMenuItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        NSUserNotificationCenter.default.delegate = self
        rebuildMenu()
        refreshButton()
    }

    // MARK: - NSUserNotificationCenter Delegate
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }

    // MARK: - Menu

    func rebuildMenu() {
        let m = NSMenu()

        // 1. 顶部状态信息面板
        let stateTitle: String
        if isRunning {
            stateTitle = isBreak ? Localized.text(zh: "▓ 休憩中", en: "▓ On Break") : Localized.text(zh: "● 专注中", en: "● Focusing")
        } else {
            stateTitle = Localized.text(zh: "○ 未开始", en: "○ Idle")
        }
        
        m.addItem(sectionLabel("\(stateTitle)"))
        
        let cyclesLeftStr = Localized.text(zh: "⏱ 剩余周期: \(currentCyclesLeft) / \(totalCycles)", en: "⏱ Cycles Left: \(currentCyclesLeft) / \(totalCycles)")
        m.addItem(sectionLabel(cyclesLeftStr))
        m.addItem(.separator())

        // 2. 控制开关
        toggleItem = item(toggleTitle(), key: "s", #selector(onToggle))
        m.addItem(toggleItem)
        m.addItem(item(Localized.text(zh: "重置当前阶段", en: "Reset Current Phase"), key: "r", #selector(onReset)))
        m.addItem(item(Localized.text(zh: "重置全部周期", en: "Reset All Cycles"), key: "R", #selector(onResetCycles)))
        m.addItem(.separator())

        // 3. 阶段快捷跳转
        m.addItem(item(Localized.text(zh: "跳过休息阶段", en: "Skip Break Phase"), key: "1", #selector(onJumpWork)))
        m.addItem(item(Localized.text(zh: "跳过工作阶段", en: "Skip Focus Phase"), key: "2", #selector(onJumpBreak)))
        m.addItem(.separator())

        // 4. 预设时长
        let presetsParent = NSMenuItem(title: Localized.text(zh: "预设时长", en: "Presets"), action: nil, keyEquivalent: "")
        let psub = NSMenu()
        [
            (Localized.text(zh: "经典番茄    25 / 5", en: "Pomodoro      25 / 5"),  25, 5),
            (Localized.text(zh: "短冲刺      15 / 3", en: "Short Sprint  15 / 3"),  15, 3),
            (Localized.text(zh: "长专注      50 / 10", en: "Long Focus    50 / 10"), 50, 10),
            (Localized.text(zh: "超长深工    90 / 20", en: "Deep Work     90 / 20"), 90, 20)
        ].forEach { title, w, b in
            let pi = NSMenuItem(title: title, action: #selector(onPreset(_:)), keyEquivalent: "")
            pi.representedObject = [w, b] as [Int]
            pi.target = self
            psub.addItem(pi)
        }
        presetsParent.submenu = psub
        m.addItem(presetsParent)

        // 5. 自定义时长
        let customParent = NSMenuItem(title: Localized.text(zh: "自定义时长", en: "Custom Duration"), action: nil, keyEquivalent: "")
        let csub = NSMenu()
        csub.addItem(sectionLabel(Localized.text(zh: "工作时长", en: "Focus Duration")))
        [10, 15, 20, 25, 30, 45, 60].forEach { v in
            let titleStr = Localized.text(zh: "\(v) 分钟", en: "\(v) Mins")
            let ci = NSMenuItem(title: titleStr, action: #selector(onSetWork(_:)), keyEquivalent: "")
            ci.state = (v == workMin) ? .on : .off
            ci.tag = v; ci.target = self; csub.addItem(ci)
        }
        csub.addItem(.separator())
        csub.addItem(sectionLabel(Localized.text(zh: "休息时长", en: "Break Duration")))
        [3, 5, 10, 15, 20].forEach { v in
            let titleStr = Localized.text(zh: "\(v) 分钟", en: "\(v) Mins")
            let ci = NSMenuItem(title: titleStr, action: #selector(onSetBreak(_:)), keyEquivalent: "")
            ci.state = (v == breakMin) ? .on : .off
            ci.tag = v; ci.target = self; csub.addItem(ci)
        }
        customParent.submenu = csub
        m.addItem(customParent)

        // 6. 周期数量设置
        let cyclesParent = NSMenuItem(title: Localized.text(zh: "周期数量", en: "Cycle Count"), action: nil, keyEquivalent: "")
        let cyclesSub = NSMenu()
        [1, 2, 3, 4, 5, 6, 7, 8].forEach { v in
            let titleStr = Localized.text(zh: " \(v) 个周期", en: " \(v) \(v == 1 ? "Cycle" : "Cycles")")
            let ci = NSMenuItem(title: titleStr, action: #selector(onSetTotalCycles(_:)), keyEquivalent: "")
            ci.state = (v == totalCycles) ? .on : .off
            ci.tag = v; ci.target = self; cyclesSub.addItem(ci)
        }
        cyclesParent.submenu = cyclesSub
        m.addItem(cyclesParent)

        // 7. 通用设置
        let settingsParent = NSMenuItem(title: Localized.text(zh: "设置", en: "Settings"), action: nil, keyEquivalent: "")
        let ssub = NSMenu()
        
        let autoItem = NSMenuItem(title: Localized.text(zh: "自动开始下一阶段", en: "Auto Advance Phase"), action: #selector(onToggleAutoAdvance), keyEquivalent: "")
        autoItem.state = autoAdvance ? .on : .off
        autoItem.target = self
        ssub.addItem(autoItem)
        
        let precItem = NSMenuItem(title: Localized.text(zh: "菜单栏显示秒数", en: "Show Seconds in Menu Bar"), action: #selector(onTogglePrecision), keyEquivalent: "")
        precItem.state = showSeconds ? .on : .off
        precItem.target = self
        ssub.addItem(precItem)
        
        settingsParent.submenu = ssub
        m.addItem(settingsParent)

        m.addItem(.separator())
        m.addItem(item(Localized.text(zh: "退出", en: "Quit"), key: "q", #selector(onQuit)))

        statusItem.menu = m
    }

    // MARK: - Actions

    @objc func onToggle() { isRunning ? pause() : start() }

    @objc func onReset() {
        stop(); remainingSeconds = 0
        rebuildMenu(); refreshButton()
    }
    
    @objc func onResetCycles() {
        stop(); remainingSeconds = 0
        currentCyclesLeft = totalCycles
        isBreak = false
        rebuildMenu(); refreshButton()
    }

    @objc func onJumpWork() {
        stop(); isBreak = false
        remainingSeconds = workMin * 60
        rebuildMenu(); start()
    }

    @objc func onJumpBreak() {
        stop(); isBreak = true
        remainingSeconds = breakMin * 60
        rebuildMenu(); start()
    }

    @objc func onPreset(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? [Int], v.count == 2 else { return }
        workMin = v[0]; breakMin = v[1]
        stop(); remainingSeconds = 0; isBreak = false
        rebuildMenu(); refreshButton()
    }

    @objc func onSetWork(_ sender: NSMenuItem) {
        workMin = sender.tag; stop(); remainingSeconds = 0
        rebuildMenu(); refreshButton()
    }

    @objc func onSetBreak(_ sender: NSMenuItem) {
        breakMin = sender.tag; stop(); remainingSeconds = 0
        rebuildMenu(); refreshButton()
    }
    
    @objc func onSetTotalCycles(_ sender: NSMenuItem) {
        totalCycles = sender.tag
        currentCyclesLeft = sender.tag
        rebuildMenu(); refreshButton()
    }

    @objc func onTogglePrecision() {
        showSeconds.toggle()
        rebuildMenu(); refreshButton()
    }
    
    @objc func onToggleAutoAdvance() {
        autoAdvance.toggle()
        rebuildMenu()
    }

    @objc func onQuit() { NSApplication.shared.terminate(nil) }

    // MARK: - Timer

    func start() {
        if remainingSeconds == 0 {
            remainingSeconds = (isBreak ? breakMin : workMin) * 60
        }
        isRunning = true
        
        timer = Timer.scheduledTimer(timeInterval: 1.0, target: self,
                                     selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        toggleItem?.title = toggleTitle()
        rebuildMenu()
        refreshButton()
    }

    func pause() {
        stop()
        toggleItem?.title = toggleTitle()
        rebuildMenu()
        refreshButton()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        isRunning = false
    }

    @objc func tick() {
        remainingSeconds = max(0, remainingSeconds - 1)
        remainingSeconds == 0 ? timerDone() : refreshButton()
    }

    func timerDone() {
        stop()
        
        let wasBreak = isBreak
        
        // 倒计时结束时的多语言通知
        let notifTitle = wasBreak ? Localized.text(zh: "工作时间开始 📌", en: "Focus Session Started 📌") : Localized.text(zh: "工作时间结束 🔔", en: "Focus Session Finished 🔔")
        let notifSubtitle = wasBreak ? Localized.text(zh: "准备好，开始新一轮的专注！", en: "Get ready to focus on your task!") : Localized.text(zh: "干得漂亮，现在休息一下吧。", en: "Great job! Time to take a break.")
        
        sendOldNotification(title: notifTitle, subtitle: notifSubtitle)
        
        if !wasBreak {
            currentCyclesLeft = max(0, currentCyclesLeft - 1)
        }
        
        if currentCyclesLeft == 0 {
            let allDoneTitle = Localized.text(zh: "🎉 恭喜！全部周期已完成", en: "🎉 Congratulations! All cycles completed")
            let allDoneSub = Localized.text(zh: "您已完成了设定的所有专注目标。", en: "You have achieved all your focus goals.")
            sendOldNotification(title: allDoneTitle, subtitle: allDoneSub)
            
            currentCyclesLeft = totalCycles
            isBreak = false
            remainingSeconds = 0
            rebuildMenu(); refreshButton()
        } else {
            isBreak.toggle()
            remainingSeconds = 0
            rebuildMenu(); refreshButton()
            
            if autoAdvance {
                start()
            }
        }
    }

    // MARK: - Display

    func refreshButton() {
        guard let btn = statusItem?.button else { return }
        
        btn.image = nil
        btn.imagePosition = .noImage
        
        let fullText: String
        if remainingSeconds > 0 {
            fullText = showSeconds ? formatSec(remainingSeconds) : formatMin(remainingSeconds)
        } else {
            let defaultSeconds = (isBreak ? breakMin : workMin) * 60
            fullText = showSeconds ? formatSec(defaultSeconds) : formatMin(defaultSeconds)
        }
        
        let font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
        let attrStr = NSAttributedString(string: fullText, attributes: [.font: font])
        
        btn.attributedTitle = attrStr
    }

    func formatSec(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    func formatMin(_ s: Int) -> String { "\((s + 59) / 60)" }

    func toggleTitle() -> String {
        if isRunning {
            return Localized.text(zh: "暂停", en: "Pause")
        } else {
            return remainingSeconds > 0 ? Localized.text(zh: "继续", en: "Resume") : Localized.text(zh: "开始", en: "Start")
        }
    }

    // MARK: - 兼容旧版系统的通知组件 (NSUserNotification)
    func sendOldNotification(title: String, subtitle: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = subtitle
        notification.soundName = "Ping"
        
        NSUserNotificationCenter.default.deliver(notification)
    }

    // MARK: - Helpers

    @discardableResult
    func item(_ title: String, key: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self; return i
    }

    func sectionLabel(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false; return i
    }
}