import UIKit

final class CameraViewController: UIViewController {
    private let engine = CameraEngine()
    private let preview = CameraPreview()
    private var options = CameraEngine.Options()
    private var current = CameraEngine.State()
    private var accent = UIColor(red: 1, green: 0.74, blue: 0, alpha: 1)
    private let header = UIStackView(), crops = UISegmentedControl(items: ["Динамический", "Фиксированный"])
    private let shapes = UISegmentedControl(items: FrameShape.allCases.map { $0.title })
    private let note = UILabel(), status = UILabel(), clock = UILabel()
    private let normal = UIButton(type: .system), horizon = UIButton(type: .system)
    private let record = UIButton(type: .custom), inner = UIView()
    private let ultra = UIButton(type: .system), wide = UIButton(type: .system)
    private let flip = UIButton(type: .system), gallery = UIButton(type: .system)
    private let torch = UIButton(type: .system), grid = UIButton(type: .system), settings = UIButton(type: .system)
    private let topShade = CAGradientLayer(), bottomShade = CAGradientLayer()
    private let screenLight = CAShapeLayer()
    private var screenLightMode = 0

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        if #available(iOS 13.0, *) { overrideUserInterfaceStyle = .dark }
        options.horizon = UserDefaults.standard.object(forKey: "horizon") as? Bool ?? true
        options.crop = CropMode(rawValue: UserDefaults.standard.integer(forKey: "crop")) ?? .dynamic
        options.shape = FrameShape(rawValue: UserDefaults.standard.integer(forKey: "shape")) ?? .portrait
        if let hex = UserDefaults.standard.string(forKey: "accent"), let value = UInt32(hex, radix: 16) { accent = UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1) }
        preview.grid = UserDefaults.standard.bool(forKey: "grid"); view.addSubview(preview)
        topShade.colors = [UIColor.black.withAlphaComponent(0.9).cgColor, UIColor.clear.cgColor]
        bottomShade.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.98).cgColor]
        view.layer.addSublayer(topShade); view.layer.addSublayer(bottomShade)
        screenLight.fillRule = .evenOdd; screenLight.isHidden = true
        view.layer.insertSublayer(screenLight, below: topShade)
        header.axis = .horizontal; header.alignment = .center; header.spacing = 12
        configure(grid, symbol: "grid", fallback: "▦", action: #selector(toggleGrid))
        configure(torch, symbol: "bolt.fill", fallback: "ϟ", action: #selector(toggleTorch))
        configure(settings, symbol: "gearshape", fallback: "⚙", action: #selector(customize))
        header.addArrangedSubview(grid); header.addArrangedSubview(shapes); header.addArrangedSubview(torch); header.addArrangedSubview(settings)
        for button in [grid, torch, settings] { button.widthAnchor.constraint(equalToConstant: 30).isActive = true }
        view.addSubview(header); view.addSubview(crops)
        [note, status, clock].forEach { $0.textColor = .white; $0.textAlignment = .center; $0.font = .systemFont(ofSize: 11); view.addSubview($0) }
        note.numberOfLines = 2; status.numberOfLines = 2
        clock.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold); clock.backgroundColor = UIColor.black.withAlphaComponent(0.55); clock.layer.cornerRadius = 12; clock.clipsToBounds = true
        for button in [normal, horizon] { button.titleLabel?.font = .systemFont(ofSize: 10, weight: .semibold); view.addSubview(button); button.addTarget(self, action: #selector(changeMode(_:)), for: .touchUpInside) }
        normal.setTitle("ОБЫЧНЫЙ", for: .normal); horizon.setTitle("СТАБИЛИЗАЦИЯ", for: .normal)
        for button in [wide, ultra] { button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold); button.layer.cornerRadius = 19; view.addSubview(button); button.addTarget(self, action: #selector(changeLens(_:)), for: .touchUpInside) }
        wide.setTitle("1×", for: .normal); ultra.setTitle("0,5×", for: .normal)
        configure(gallery, symbol: "photo.on.rectangle", fallback: "▧", action: #selector(openGallery))
        configure(flip, symbol: "arrow.triangle.2.circlepath.camera", fallback: "↻", action: #selector(flipCamera))
        view.addSubview(gallery); view.addSubview(flip); view.addSubview(record)
        record.layer.cornerRadius = 35; record.layer.borderWidth = 2; record.layer.borderColor = UIColor.white.cgColor
        inner.isUserInteractionEnabled = false; record.addSubview(inner)
        record.addTarget(self, action: #selector(toggleRecord), for: .touchUpInside)
        record.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(still(_:))))
        record.accessibilityLabel = "Запись видео"; record.accessibilityHint = "Удерживание сохраняет стоп-кадр"
        gallery.accessibilityLabel = "Записи"; flip.accessibilityLabel = "Сменить камеру"; torch.accessibilityLabel = "Фонарик"; settings.accessibilityLabel = "Оформление"
        shapes.addTarget(self, action: #selector(changeShape), for: .valueChanged); crops.addTarget(self, action: #selector(changeCrop), for: .valueChanged)
        engine.onFrame = { [weak preview = self.preview] frame in preview?.display(frame) }
        engine.onState = { [weak self] state in self?.current = state; self?.render() }
        engine.onSaved = { [weak self] _ in self?.flashSaved() }
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
        engine.update(options); render()
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); engine.start(); preview.isPaused = false }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        offerStabilization()
    }
    private func offerStabilization() {
        guard current.ready, view.window != nil, !UserDefaults.standard.bool(forKey: "stabilizationOfferShown"), presentedViewController == nil else { return }
        let offer = UIAlertController(title: "Включить стабилизацию?", message: "Горизонт выравнивается по датчикам движения. Держите телефон вертикально и плавно наклоните влево или вправо: угол появится над кнопкой записи. Края кадра обрезаются; это не замена оптической стабилизации.", preferredStyle: .alert)
        for (title, enabled) in [("Включить", true), ("Обычная съёмка", false)] {
            offer.addAction(UIAlertAction(title: title, style: .default) { _ in
                UserDefaults.standard.set(true, forKey: "stabilizationOfferShown")
                self.options.horizon = enabled; self.commit()
            })
        }
        present(offer, animated: true)
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); engine.stop(); preview.isPaused = true }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds, safe = view.safeAreaInsets
        preview.frame = b
        screenLight.frame = b
        let lightPath = UIBezierPath(rect: b)
        lightPath.append(UIBezierPath(roundedRect: b.insetBy(dx: 28, dy: 104), cornerRadius: 28))
        screenLight.path = lightPath.cgPath
        topShade.frame = CGRect(x: 0, y: 0, width: b.width, height: safe.top + 175)
        bottomShade.frame = CGRect(x: 0, y: b.height - safe.bottom - 245, width: b.width, height: safe.bottom + 245)
        header.frame = CGRect(x: 18, y: safe.top + 14, width: b.width - 36, height: 36)
        crops.frame = CGRect(x: (b.width - 250) / 2, y: header.frame.maxY + 10, width: 250, height: 32)
        note.frame = CGRect(x: 24, y: crops.frame.maxY + 6, width: b.width - 48, height: 34)
        let bottom = b.height - safe.bottom - 12
        record.frame = CGRect(x: b.midX - 35, y: bottom - 70, width: 70, height: 70)
        inner.frame = current.recording ? CGRect(x: 23, y: 23, width: 24, height: 24) : CGRect(x: 7, y: 7, width: 56, height: 56)
        inner.layer.cornerRadius = current.recording ? 5 : 28
        gallery.frame = CGRect(x: 30, y: bottom - 60, width: 48, height: 48); flip.frame = CGRect(x: b.width - 78, y: bottom - 60, width: 48, height: 48)
        let lensY = record.frame.minY - 53
        wide.frame = CGRect(x: b.midX - (current.ultraWide && !current.front ? 43 : 19), y: lensY, width: 38, height: 38)
        ultra.frame = CGRect(x: b.midX + 5, y: lensY, width: 38, height: 38)
        normal.frame = CGRect(x: 16, y: lensY - 48, width: b.width / 2 - 20, height: 34)
        horizon.frame = CGRect(x: b.midX + 4, y: lensY - 48, width: b.width / 2 - 20, height: 34)
        status.frame = CGRect(x: 18, y: lensY - 80, width: b.width - 36, height: 28)
        clock.frame = CGRect(x: 16, y: safe.top + 12, width: 96, height: 28)
    }

    private func configure(_ button: UIButton, symbol: String, fallback: String, action: Selector) {
        if #available(iOS 13.0, *), let image = UIImage(systemName: symbol) { button.setImage(image, for: .normal) }
        else { button.setTitle(fallback, for: .normal); button.titleLabel?.font = .systemFont(ofSize: 26) }
        button.tintColor = .white; button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func render() {
        let busy = current.recording || current.finishing
        if !current.motionAvailable { options.horizon = false }
        shapes.selectedSegmentIndex = options.shape.rawValue; crops.selectedSegmentIndex = options.crop.rawValue
        [shapes, crops].forEach { $0.tintColor = accent; if #available(iOS 13.0, *) { $0.selectedSegmentTintColor = accent }; $0.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 11, weight: .semibold)], for: .normal); $0.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected); $0.isEnabled = !busy }
        note.text = options.crop == .dynamic ? "Увеличивает масштаб только при наклоне телефона." : "Постоянный кроп — без изменения масштаба при наклоне."
        note.isHidden = busy || !options.horizon; crops.isHidden = busy || !options.horizon; header.isHidden = busy
        normal.setTitleColor(options.horizon ? .lightGray : accent, for: .normal); horizon.setTitleColor(options.horizon ? accent : .lightGray, for: .normal)
        normal.isEnabled = !busy; horizon.isEnabled = !busy && current.motionAvailable
        ultra.isHidden = !current.ultraWide || current.front; ultra.isEnabled = !busy; wide.isEnabled = !busy
        wide.backgroundColor = current.ultraSelected ? UIColor(white: 0.18, alpha: 0.9) : accent; wide.setTitleColor(current.ultraSelected ? .white : .black, for: .normal)
        ultra.backgroundColor = current.ultraSelected ? accent : UIColor(white: 0.18, alpha: 0.9); ultra.setTitleColor(current.ultraSelected ? .black : .white, for: .normal)
        flip.isEnabled = !busy; gallery.isEnabled = !busy; settings.isEnabled = !busy
        torch.tintColor = current.torch ? accent : .white
        inner.backgroundColor = accent; record.isEnabled = current.ready && !current.finishing; record.alpha = record.isEnabled ? 1 : 0.4
        status.text = options.horizon && current.ready ? "\(current.motionStatus) · \(Int(current.tilt.rounded()))°\n\(current.message)" : current.message; clock.isHidden = !current.recording
        let seconds = Int(current.duration); clock.text = String(format: "● %02d:%02d", seconds / 60, seconds % 60); clock.textColor = accent
        UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: { self.view.setNeedsLayout(); self.view.layoutIfNeeded() })
        offerStabilization()
    }

    private func commit() {
        UserDefaults.standard.set(options.horizon, forKey: "horizon"); UserDefaults.standard.set(options.crop.rawValue, forKey: "crop"); UserDefaults.standard.set(options.shape.rawValue, forKey: "shape")
        engine.update(options); render()
    }
    @objc private func changeMode(_ sender: UIButton) { options.horizon = sender === horizon; commit() }
    @objc private func changeCrop() { options.crop = CropMode(rawValue: crops.selectedSegmentIndex) ?? .dynamic; commit() }
    @objc private func changeShape() { options.shape = FrameShape(rawValue: shapes.selectedSegmentIndex) ?? .portrait; commit() }
    @objc private func toggleGrid() { preview.grid.toggle(); UserDefaults.standard.set(preview.grid, forKey: "grid"); grid.tintColor = preview.grid ? accent : .white }
    @objc private func toggleTorch() { engine.toggleTorch() }
    @objc private func flipCamera() { engine.chooseCamera(front: !current.front) }
    @objc private func changeLens(_ sender: UIButton) { engine.chooseCamera(front: false, ultraWide: sender === ultra) }
    @objc private func toggleRecord() { UIImpactFeedbackGenerator(style: .light).impactOccurred(); engine.toggleRecording() }
    @objc private func still(_ recognizer: UILongPressGestureRecognizer) { if recognizer.state == .began { engine.stillFrame() } }
    @objc private func background() { engine.stop(); preview.isPaused = true }
    @objc private func foreground() { if presentedViewController == nil { engine.start(); preview.isPaused = false } }
    @objc private func openGallery() {
        let library = LibraryViewController(); library.theme = accent
        let nav = UINavigationController(rootViewController: library); nav.modalPresentationStyle = .fullScreen; present(nav, animated: true)
    }
    @objc private func customize() {
        let menu = UIAlertController(title: "Nulora Camera", message: "Стабилизация удерживает горизонт при наклоне. Дрожание и шаги полностью не устраняются. Цвет светодиодов True Tone системой выбирается автоматически.", preferredStyle: .actionSheet)
        for (name, value) in [("Вспышка: выключить", Float(0)), ("Вспышка: мягкая", Float(0.15)), ("Вспышка: средняя", Float(0.4)), ("Вспышка: яркая", Float(0.75))] {
            menu.addAction(UIAlertAction(title: name, style: .default) { _ in self.engine.setTorchBrightness(value) })
        }
        for (title, mode) in [("Экранный свет: белый", 1), ("Экранный свет: тёплый жёлтый", 2), ("Выключить экранный свет", 0)] {
            menu.addAction(UIAlertAction(title: title, style: .default) { _ in
                self.screenLightMode = mode
                self.screenLight.fillColor = (mode == 2 ? UIColor(red: 1, green: 0.73, blue: 0.30, alpha: 1) : UIColor.white).cgColor
                self.screenLight.isHidden = mode == 0
                self.status.text = mode == 0 ? self.current.message : "Экранный свет — цвет заднего светодиода не изменяется"
            })
        }
        menu.addAction(UIAlertAction(title: options.horizon ? "Выключить стабилизацию" : "Включить стабилизацию", style: .default) { _ in self.options.horizon.toggle(); self.commit() })
        for (name, hex) in [("Жёлтый, как в видео", "FFBD00"), ("Фиолетовый", "8B5CF6"), ("Зелёный", "33C887"), ("Коралловый", "FF6666")] {
            menu.addAction(UIAlertAction(title: name, style: .default) { _ in
                let value = UInt32(hex, radix: 16)!
                self.accent = UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
                UserDefaults.standard.set(hex, forKey: "accent"); self.render()
            })
        }
        menu.addAction(UIAlertAction(title: "Разрешения камеры и микрофона", style: .default) { _ in if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } })
        menu.addAction(UIAlertAction(title: "Закрыть", style: .cancel)); menu.popoverPresentationController?.sourceView = settings
        present(menu, animated: true)
    }
    private func flashSaved() {
        let flash = UIView(frame: view.bounds); flash.backgroundColor = UIColor.white.withAlphaComponent(0.3); flash.isUserInteractionEnabled = false; view.addSubview(flash)
        UIView.animate(withDuration: 0.25, animations: { flash.alpha = 0 }) { _ in flash.removeFromSuperview() }
    }
}
