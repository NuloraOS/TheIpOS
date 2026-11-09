import UIKit

final class CameraViewController: UIViewController {
    private let engine = CameraEngine(), preview = CameraPreview()
    private var options = CameraEngine.Options(), current = CameraEngine.State()
    private let top = UIView(), bottom = UIView()
    private let ratios = UISegmentedControl(items: FrameShape.allCases.map { $0.title })
    private let modes = UISegmentedControl(items: ["ФОТО", "ВИДЕО"])
    private let settings = UIButton(type: .system), grid = UIButton(type: .system), torch = UIButton(type: .system)
    private let gallery = UIButton(type: .system), flip = UIButton(type: .system), record = UIButton(type: .custom)
    private let inner = UIView(), status = UILabel(), zoomLabel = UILabel(), clock = UILabel()
    private let zooms = UIStackView()
    private var zoomButtons: [UIButton] = [], zoomFactor = 1.0, pinchBase = 1.0
    private let light = CAShapeLayer()
    private var lightMode = 0
    private var previousControls = ""
    private var visible = false
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        if #available(iOS 13.0, *) { overrideUserInterfaceStyle = .dark }
        options.horizon = UserDefaults.standard.bool(forKey: "horizon")
        options.crop = CropMode(rawValue: UserDefaults.standard.integer(forKey: "crop")) ?? .dynamic
        options.shape = FrameShape(rawValue: UserDefaults.standard.integer(forKey: "shape")) ?? .portrait
        lightMode = UserDefaults.standard.integer(forKey: "screenLight")
        preview.grid = UserDefaults.standard.bool(forKey: "grid")
        view.addSubview(preview)
        light.fillRule = .evenOdd; view.layer.addSublayer(light)
        top.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        bottom.backgroundColor = UIColor.black.withAlphaComponent(0.88)
        view.addSubview(top); view.addSubview(bottom)
        button(settings, "Параметры", #selector(openSettings)); button(grid, "Сетка", #selector(toggleGrid)); button(torch, "Вспышка", #selector(toggleTorch))
        button(gallery, "Галерея", #selector(openGallery)); button(flip, "Сменить", #selector(flipCamera))
        for control in [settings, grid, torch, gallery, flip] { view.addSubview(control) }
        for segment in [ratios, modes] {
            segment.tintColor = .white
            segment.setTitleTextAttributes([.foregroundColor: UIColor.lightGray, .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .normal)
            segment.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
            if #available(iOS 13.0, *) { segment.selectedSegmentTintColor = .white }
            view.addSubview(segment)
        }
        ratios.selectedSegmentIndex = options.shape.rawValue; modes.selectedSegmentIndex = 1
        ratios.addTarget(self, action: #selector(changeRatio), for: .valueChanged)
        modes.addTarget(self, action: #selector(changeMode), for: .valueChanged)
        record.layer.borderWidth = 2; record.layer.borderColor = UIColor.white.cgColor; record.layer.cornerRadius = 36
        inner.backgroundColor = .white; inner.isUserInteractionEnabled = false; record.addSubview(inner)
        record.addTarget(self, action: #selector(shutter), for: .touchUpInside); view.addSubview(record)
        record.accessibilityLabel = "Начать запись"
        zooms.axis = .horizontal; zooms.distribution = .fillEqually; zooms.spacing = 5
        for (index, value) in [1,2,5,10,100].enumerated() {
            let b = UIButton(type: .system); b.tag = index
            button(b, "\(value)×", #selector(selectZoom(_:)))
            b.layer.cornerRadius = 20; b.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            zooms.addArrangedSubview(b); zoomButtons.append(b)
        }
        view.addSubview(zooms)
        for label in [status, zoomLabel, clock] { label.textColor = .white; label.textAlignment = .center; label.font = .systemFont(ofSize: 11); view.addSubview(label) }
        status.numberOfLines = 2; clock.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        zoomLabel.text = "1×"; zoomLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))); preview.addGestureRecognizer(pinch)
        engine.onFrame = { [weak self] frame in self?.preview.display(frame) }
        engine.onState = { [weak self] state in guard let self = self else { return }; self.current = state; self.render() }
        engine.onSaved = { [weak self] url in self?.saved(url) }
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
        engine.update(options); applyLight(); render()
    }
    private func button(_ button: UIButton, _ title: String, _ action: Selector) {
        button.setTitle(title, for: .normal); button.tintColor = .white
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        button.addTarget(self, action: action, for: .touchUpInside)
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); visible = true; engine.start() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); visible = false; engine.stop(); preview.clear() }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds, safe = view.safeAreaInsets, end = b.height - safe.bottom - 10
        preview.frame = b
        top.frame = CGRect(x: 0, y: 0, width: b.width, height: safe.top + 94)
        bottom.frame = CGRect(x: 0, y: end - 188, width: b.width, height: b.height - end + 188)
        grid.frame = CGRect(x: 8, y: safe.top, width: 80, height: 44)
        torch.frame = CGRect(x: b.midX - 44, y: safe.top, width: 88, height: 44)
        settings.frame = CGRect(x: b.width - 96, y: safe.top, width: 88, height: 44)
        ratios.frame = CGRect(x: 22, y: safe.top + 48, width: b.width - 44, height: 32)
        record.frame = CGRect(x: b.midX - 36, y: end - 72, width: 72, height: 72)
        inner.frame = current.recording ? CGRect(x: 24, y: 24, width: 24, height: 24) : CGRect(x: 7, y: 7, width: 58, height: 58)
        inner.layer.cornerRadius = current.recording ? 5 : 29
        gallery.frame = CGRect(x: 16, y: end - 66, width: 76, height: 60)
        flip.frame = CGRect(x: b.width - 92, y: end - 66, width: 76, height: 60)
        modes.frame = CGRect(x: b.midX - 98, y: end - 116, width: 196, height: 30)
        zooms.frame = CGRect(x: 18, y: end - 168, width: b.width - 36, height: 44)
        status.frame = CGRect(x: 16, y: end - 207, width: b.width - 32, height: 34)
        zoomLabel.frame = CGRect(x: b.midX - 60, y: safe.top + 104, width: 120, height: 26)
        clock.frame = CGRect(x: b.midX - 62, y: safe.top + 84, width: 124, height: 23)
        light.frame = b
        let border = UIBezierPath(rect: b); border.append(UIBezierPath(roundedRect: b.insetBy(dx: 24, dy: 125), cornerRadius: 20)); light.path = border.cgPath
    }
    private func render() {
        let busy = current.recording || current.finishing
        clock.isHidden = !current.recording
        let seconds = Int(current.duration); clock.text = String(format: "● %02d:%02d", seconds/60, seconds%60)
        status.text = options.horizon && current.ready ? "\(current.motionStatus) · \(Int(current.tilt.rounded()))°\n\(current.message)" : current.message
        let key = "\(current.ready)-\(current.recording)-\(current.finishing)-\(current.torch)-\(current.front)-\(modes.selectedSegmentIndex)"
        guard key != previousControls else { return }; previousControls = key
        for control in [ratios, modes] { control.isEnabled = !busy }
        for control in [gallery, flip, settings] { control.isEnabled = !busy }
        record.isEnabled = current.ready && !current.finishing; record.alpha = record.isEnabled ? 1 : 0.4
        record.accessibilityLabel = modes.selectedSegmentIndex == 0 ? "Сделать фото" : current.recording ? "Остановить запись" : "Начать запись"
        torch.isEnabled = !current.front; torch.setTitle(current.torch ? "Свет вкл." : "Вспышка", for: .normal)
        view.setNeedsLayout() // No animation or reconstruction on every sensor/timer update.
    }
    private func commit() {
        UserDefaults.standard.set(options.horizon, forKey: "horizon"); UserDefaults.standard.set(options.crop.rawValue, forKey: "crop"); UserDefaults.standard.set(options.shape.rawValue, forKey: "shape")
        engine.update(options); previousControls = ""; render()
    }
    @objc private func changeRatio() { options.shape = FrameShape(rawValue: ratios.selectedSegmentIndex) ?? .portrait; commit() }
    @objc private func changeMode() { previousControls = ""; render() }
    @objc private func shutter() { if modes.selectedSegmentIndex == 0 { engine.stillFrame() } else { engine.toggleRecording() } }
    @objc private func flipCamera() { engine.chooseCamera(front: !current.front) }
    @objc private func toggleTorch() { engine.toggleTorch() }
    @objc private func toggleGrid() { preview.grid.toggle(); UserDefaults.standard.set(preview.grid, forKey: "grid"); grid.setTitle(preview.grid ? "Сетка вкл." : "Сетка", for: .normal) }
    @objc private func selectZoom(_ button: UIButton) { setZoom([1.0,2,5,10,100][button.tag]) }
    private func setZoom(_ value: Double) {
        zoomFactor = min(100,CameraZoom.clamp(value)); engine.setZoom(zoomFactor)
        zoomLabel.text = String(format: "%.1f×", zoomFactor)
        for b in zoomButtons { let selected = abs([1.0,2,5,10,100][b.tag] - zoomFactor) < 0.05; b.backgroundColor = selected ? .white : UIColor(white: 0.15, alpha: 0.9); b.setTitleColor(selected ? .black : .white, for: .normal) }
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) { if gesture.state == .began { pinchBase = zoomFactor }; setZoom(pinchBase * Double(gesture.scale)) }
    @objc private func background() { engine.stop(); preview.clear() }
    @objc private func foreground() { if visible && presentedViewController == nil { engine.start() } }
    @objc private func openGallery() {
        guard !current.recording && !current.finishing else { return }
        let nav = UINavigationController(rootViewController: LibraryViewController()); nav.modalPresentationStyle = .fullScreen; present(nav, animated: true)
    }
    @objc private func openSettings() {
        let controller = CameraSettingsController(options: options, grid: preview.grid, light: lightMode)
        controller.apply = { [weak self] options, grid, light in
            guard let self = self else { return }
            self.options = options; self.preview.grid = grid; self.lightMode = light
            UserDefaults.standard.set(grid, forKey: "grid"); UserDefaults.standard.set(light, forKey: "screenLight")
            self.applyLight(); self.commit()
        }
        let nav = UINavigationController(rootViewController: controller); nav.modalPresentationStyle = .fullScreen; present(nav, animated: true)
    }
    private func applyLight() { light.isHidden = lightMode == 0; light.fillColor = (lightMode == 2 ? UIColor(red:1,green:0.73,blue:0.3,alpha:1) : UIColor.white).cgColor }
    private func saved(_ url: URL) {
        status.text = "Сохранено в галерее"
        LibraryThumbnail.load(url: url, size: CGSize(width: 76, height: 60)) { [weak self] image in
            self?.gallery.setBackgroundImage(image, for: .normal); self?.gallery.layer.cornerRadius = 12; self?.gallery.clipsToBounds = true
            self?.gallery.setTitle(image == nil ? "Галерея" : "", for: .normal)
        }
    }
    #if targetEnvironment(simulator)
    func checkInterface() -> [String] {
        loadViewIfNeeded(); view.frame = CGRect(x:0,y:0,width:320,height:568); view.setNeedsLayout(); view.layoutIfNeeded()
        var errors: [String] = []
        for button in [settings, grid, torch, gallery, flip, record] {
            if button.frame.height < 44 || button.frame.width < 44 { errors.append("Touch target smaller than 44") }
            if !view.bounds.contains(button.frame) { errors.append("Button outside viewport") }
            if button.allTargets.isEmpty { errors.append("Button has no action") }
        }
        if record.frame.intersects(gallery.frame) || record.frame.intersects(flip.frame) { errors.append("Shutter overlaps controls") }
        setZoom(100); if zoomFactor != 100 { errors.append("100x zoom unavailable") }; setZoom(1)
        return errors
    }
    #endif
}

final class CameraSettingsController: UITableViewController {
    var apply: ((CameraEngine.Options, Bool, Int) -> Void)?
    private var options: CameraEngine.Options, grid: Bool, light: Int
    init(options: CameraEngine.Options, grid: Bool, light: Int) { self.options = options; self.grid = grid; self.light = light; super.init(style: .grouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Параметры"; view.backgroundColor = .black
        navigationController?.navigationBar.barStyle = .black; navigationController?.navigationBar.tintColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(close))
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 3 : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Съёмка" : "Экранный свет" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 0 ? "Стабилизация удерживает горизонт с кропом кадра. Зум до 100× — цифровой: качество при сильном увеличении снижается." : "Белый и тёплый жёлтый свет создаётся экраном. Цвет задних светодиодов не меняется." }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.backgroundColor = UIColor(white:0.08,alpha:1); cell.textLabel?.textColor = .white; cell.selectionStyle = .none
        if indexPath.section == 1 || indexPath.row == 2 {
            let lightRow = indexPath.section == 1
            cell.textLabel?.text = lightRow ? "Свет" : "Кроп"
            let segment = UISegmentedControl(items: lightRow ? ["Выкл.","Белый","Жёлтый"] : ["Динам.","Фикс."])
            segment.tag = lightRow ? 3 : 2; segment.frame.size = CGSize(width: lightRow ? 206 : 170, height: 32)
            segment.selectedSegmentIndex = lightRow ? light : options.crop.rawValue; segment.tintColor = .white
            segment.addTarget(self, action: #selector(changeSegment(_:)), for: .valueChanged); cell.accessoryView = segment
        } else {
            cell.textLabel?.text = indexPath.row == 0 ? "Стабилизация" : "Сетка"
            let control = UISwitch(); control.onTintColor = .gray; control.isOn = indexPath.row == 0 ? options.horizon : grid; control.tag = indexPath.row
            control.addTarget(self, action: #selector(changeSwitch(_:)), for: .valueChanged); cell.accessoryView = control
        }
        return cell
    }
    @objc private func changeSwitch(_ control: UISwitch) { if control.tag == 0 { options.horizon = control.isOn } else { grid = control.isOn }; apply?(options, grid, light) }
    @objc private func changeSegment(_ control: UISegmentedControl) { if control.tag == 3 { light = control.selectedSegmentIndex } else { options.crop = CropMode(rawValue: control.selectedSegmentIndex) ?? .dynamic }; apply?(options, grid, light) }
    @objc private func close() { dismiss(animated: true) }
}
