import UIKit
import AVFoundation
import CoreImage

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = Bundle.main.bundleIdentifier == "com.theipos.o2camera" ? O2CameraViewController() : CameraViewController()
        window?.makeKeyAndVisible()
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-probe"), let window = window { CameraUIProbe.run(window) }
        #endif
        return true
    }
}

// Separate app using our own camera pipeline and UI artwork. The recording backend is never set by demo labels.
final class O2CameraViewController: UIViewController {
    private let engine = CameraEngine(), preview = CameraPreview()
    private var options = CameraEngine.Options(), state = CameraEngine.State()
    private let orange = UIColor(red:1,green:0.49,blue:0.06,alpha:1)
    private let top = UIView(), bottom = UIView(), shutter = UIButton(type:.custom), center = UIView()
    private let flash = UIButton(type:.system), exposure = UIButton(type:.system), format = UIButton(type:.system), menu = UIButton(type:.system)
    private let gallery = UIButton(type:.system), flip = UIButton(type:.system), stabilization = UIButton(type:.system), focus = UIButton(type:.system)
    private let modeStrip = UIScrollView(), modes = UIStackView(), lenses = UIStackView(), manual = UIStackView()
    private let toast = UILabel(), clock = UILabel(), dial = O2ZoomDial(), slider = UISlider()
    private let horizonMap = HorizonMapView()
    private var mode = 2, zoom = 1.0, pinchStart = 1.0, activeParameter = "EV", demoFormat = "1080·30", lastControls = ""
    private var toastTicket = 0, visible = false
    private var zoomHoldStart = CGPoint.zero, zoomHoldValue = 1.0, dialTicket = 0
    private var panel:UIView?, lastMessage = ""
    private var panelActions:[()->Void] = []
    private var modeButtons: [UIButton] = [], zoomButtons: [UIButton] = []
    override var preferredStatusBarStyle:UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask { .portrait }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        if #available(iOS 13.0, *) { overrideUserInterfaceStyle = .dark }
        options.resolution = 1080; options.horizon = false
        view.addSubview(preview); top.backgroundColor = UIColor.black.withAlphaComponent(0.8); bottom.backgroundColor = .black
        view.addSubview(top); view.addSubview(bottom)
        configure(flash,"ϟ",#selector(toggleFlash)); configure(exposure,"EV 0.0",#selector(openExposure)); configure(format,demoFormat,#selector(chooseFormat)); configure(menu,"⠿",#selector(openMenu))
        configure(gallery,"▧",#selector(openGallery)); configure(flip,"↻",#selector(flipCamera)); configure(stabilization,"◉",#selector(toggleStabilization)); configure(focus,"⌾",#selector(centerFocus))
        for b in [flash,exposure,format,menu,gallery,flip,stabilization,focus] { view.addSubview(b) }
        view.addSubview(horizonMap)
        artwork(flash,"flash_off");artwork(flip,"flip");artwork(menu,"menu");artwork(stabilization,"stabilization")
        shutter.layer.cornerRadius = 34; shutter.layer.borderWidth = 2; shutter.layer.borderColor = UIColor(white:0.35,alpha:1).cgColor
        center.isUserInteractionEnabled = false; shutter.addSubview(center); shutter.addTarget(self,action:#selector(capture),for:.touchUpInside); view.addSubview(shutter)
        modes.axis = .horizontal; modes.spacing = 2
        for (i,title) in ["МАСТЕР","ВИДЕО","ФОТО","ПОРТРЕТ","ЕЩЁ"].enumerated() { let b = UIButton(type:.system);configure(b,title,#selector(changeMode(_:)));b.tag=i;b.titleLabel?.font = .systemFont(ofSize:9,weight:.bold); b.contentEdgeInsets = UIEdgeInsets(top:0,left:8,bottom:0,right:8);b.heightAnchor.constraint(equalToConstant:44).isActive=true;b.layer.cornerRadius=22;modes.addArrangedSubview(b);modeButtons.append(b) }
        modeStrip.showsHorizontalScrollIndicator = false;modeStrip.addSubview(modes);view.addSubview(modeStrip)
        lenses.axis = .horizontal; lenses.distribution = .fillEqually; lenses.spacing = 3
        for (i,title) in ["1×","2","3","6","120×"].enumerated() {
            let b=UIButton(type:.system);configure(b,title,#selector(lens(_:)));b.tag=i;b.layer.cornerRadius=20
            let hold=UILongPressGestureRecognizer(target:self,action:#selector(holdZoom(_:)));hold.minimumPressDuration=0.22;hold.allowableMovement=20;hold.cancelsTouchesInView=true;b.addGestureRecognizer(hold)
            lenses.addArrangedSubview(b);zoomButtons.append(b)
        }; view.addSubview(lenses)
        manual.axis = .horizontal; manual.distribution = .fillEqually
        for name in ["ISO","S","EV","AF","WB"] { let b=UIButton(type:.system);configure(b,name,#selector(parameter(_:)));manual.addArrangedSubview(b) }; view.addSubview(manual)
        slider.tintColor = orange;slider.isHidden=true;slider.isContinuous=false;slider.addTarget(self,action:#selector(parameterChanged),for:.valueChanged);view.addSubview(slider)
        toast.textColor = .white;toast.font = .systemFont(ofSize:12);toast.textAlignment = .center;toast.backgroundColor = UIColor(white:0.18,alpha:0.95);toast.layer.cornerRadius=7;toast.clipsToBounds=true;toast.numberOfLines=2;toast.alpha=0;view.addSubview(toast)
        clock.textColor = .white;clock.font = .monospacedDigitSystemFont(ofSize:13,weight:.semibold);clock.textAlignment = .center;view.addSubview(clock)
        dial.isHidden=true;dial.onChange={ [weak self] value in self?.setZoom(value) };view.insertSubview(dial,belowSubview:shutter)
        let pinch=UIPinchGestureRecognizer(target:self,action:#selector(pinch(_:)));preview.addGestureRecognizer(pinch)
        let tap=UITapGestureRecognizer(target:self,action:#selector(tapFocus(_:)));preview.addGestureRecognizer(tap)
        engine.onFrame={ [weak self] image in self?.preview.display(image) }
        engine.onState={ [weak self] value in self?.state=value;self?.render() }
        engine.onSaved={ [weak self] url in self?.say("Сохранено в галерее");LibraryThumbnail.load(url:url,size:CGSize(width:52,height:52)){[weak self] image in self?.gallery.setBackgroundImage(image,for:.normal);self?.gallery.setTitle(image == nil ? "▧" : "",for:.normal);self?.gallery.clipsToBounds=true;self?.gallery.layer.cornerRadius=10} }
        NotificationCenter.default.addObserver(self,selector:#selector(background),name:UIApplication.didEnterBackgroundNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(foreground),name:UIApplication.didBecomeActiveNotification,object:nil)
        engine.update(options);setZoom(1);render()
    }
    private func configure(_ b:UIButton,_ title:String,_ selector:Selector){b.setTitle(title,for:.normal);b.tintColor = .white;b.titleLabel?.font = .systemFont(ofSize:13,weight:.medium);b.addTarget(self,action:selector,for:.touchUpInside)}
    private func artwork(_ button:UIButton,_ name:String){guard let image=UIImage(named:"O2_"+name) else{return};button.setImage(image.withRenderingMode(.alwaysOriginal),for:.normal);button.setTitle("",for:.normal);button.imageView?.contentMode = .scaleAspectFit}
    override func viewWillAppear(_ animated:Bool){super.viewWillAppear(animated);visible=true;engine.start()}
    override func viewWillDisappear(_ animated:Bool){super.viewWillDisappear(animated);visible=false;engine.stop();preview.clear()}
    deinit{NotificationCenter.default.removeObserver(self)}
    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews();let b=view.bounds,safe=view.safeAreaInsets,end=b.height-safe.bottom
        preview.frame=b;top.frame=CGRect(x:0,y:0,width:b.width,height:safe.top+48);bottom.frame=CGRect(x:0,y:end-158,width:b.width,height:b.height-end+158)
        flash.frame=CGRect(x:6,y:safe.top,width:44,height:44);exposure.frame=CGRect(x:50,y:safe.top,width:82,height:44);format.frame=CGRect(x:b.width-134,y:safe.top,width:84,height:44);menu.frame=CGRect(x:b.width-50,y:safe.top,width:44,height:44)
        shutter.frame=CGRect(x:b.midX-34,y:end-117,width:68,height:68);center.frame=state.recording ? CGRect(x:23,y:23,width:22,height:22) : CGRect(x:6,y:6,width:56,height:56);center.layer.cornerRadius=state.recording ? 5 : 28
        gallery.frame=CGRect(x:22,y:end-111,width:52,height:52);flip.frame=CGRect(x:b.width-74,y:end-111,width:52,height:52)
        modeStrip.frame=CGRect(x:8,y:end-49,width:b.width-16,height:44);let fit=modes.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize);modes.frame=CGRect(x:0,y:0,width:max(fit.width,modeStrip.bounds.width),height:44);modeStrip.contentSize=modes.bounds.size
        focus.frame=CGRect(x:4,y:end-166,width:44,height:44);stabilization.frame=CGRect(x:b.width-48,y:end-166,width:44,height:44);lenses.frame=CGRect(x:50,y:end-166,width:b.width-100,height:44)
        manual.frame=CGRect(x:10,y:end-211,width:b.width-20,height:44)
        slider.frame=CGRect(x:30,y:end-252,width:b.width-60,height:36)
        dial.frame=CGRect(x:0,y:end-292,width:b.width,height:175)
        toast.frame=CGRect(x:28,y:safe.top+54,width:b.width-56,height:44);clock.frame=CGRect(x:b.midX-60,y:safe.top+48,width:120,height:28)
        horizonMap.frame=CGRect(x:b.width-88,y:safe.top+105,width:72,height:98)
    }
    private func render(){
        if state.message != lastMessage { lastMessage=state.message; say(state.message) }
        horizonMap.isHidden = !options.horizon;horizonMap.setAngle(state.tilt,ready:state.motionReady)
        let busy=state.recording || state.finishing
        clock.isHidden = !state.recording;let seconds=Int(state.duration);clock.text=String(format:"● %02d:%02d",seconds/60,seconds%60)
        let key="\(mode)-\(state.ready)-\(state.recording)-\(state.finishing)-\(options.horizon)"
        guard key != lastControls else{return};lastControls=key
        for b in modeButtons{b.isEnabled = !busy;b.setTitleColor(b.tag==mode ? orange : .lightGray,for:.normal);b.backgroundColor=b.tag==mode ? UIColor(white:0.13,alpha:1) : .clear}
        center.backgroundColor = mode==1 ? UIColor(red:0.95,green:0.16,blue:0.18,alpha:1) : orange
        shutter.isEnabled=(state.ready || state.recording) && !state.finishing;shutter.alpha=shutter.isEnabled ? 1 : 0.4
        artwork(flash,state.torch ? "flash_on" : "flash_off")
        shutter.accessibilityLabel=mode==1 ? (state.recording ? "Остановить видео" : "Записать видео") : "Сделать фото"
        manual.isHidden=mode != 0;gallery.isEnabled = !busy;flip.isEnabled = !busy;format.isEnabled = !busy;menu.isEnabled = !busy
        stabilization.tintColor=options.horizon ? orange : .white;view.setNeedsLayout()
    }
    @objc private func capture(){ if mode==1 {engine.toggleRecording()} else{engine.stillFrame()} }
    @objc private func changeMode(_ b:UIButton){
        if b.tag==4{openMore();return};mode=b.tag;slider.isHidden=true;dial.isHidden=true;lastControls=""
        UIView.animate(withDuration:0.25,delay:0,options:[.beginFromCurrentState,.allowUserInteraction,.curveEaseInOut],animations:{self.render();self.view.layoutIfNeeded()})
        if mode==3{say("Портрет: демонстрационный интерфейс")}
    }
    @objc private func lens(_ b:UIButton){setZoom([1.0,2,3,6,120][b.tag])}
    private func showZoomDial(){
        dialTicket += 1
        guard dial.isHidden else{return}
        dial.isHidden=false;dial.alpha=0;dial.transform=CGAffineTransform(translationX:0,y:18)
        UIView.animate(withDuration:0.347,delay:0.07,options:[.beginFromCurrentState,.allowUserInteraction,.curveEaseOut],animations:{self.dial.alpha=1;self.dial.transform = .identity})
    }
    private func hideZoomDialLater(){
        dialTicket += 1;let ticket=dialTicket
        DispatchQueue.main.asyncAfter(deadline:.now()+0.7){[weak self] in
            guard let self=self,self.dialTicket==ticket else{return}
            UIView.animate(withDuration:0.18,delay:0,options:[.beginFromCurrentState,.allowUserInteraction,.curveEaseIn],animations:{self.dial.alpha=0;self.dial.transform=CGAffineTransform(translationX:0,y:12)}){_ in if self.dialTicket==ticket{self.dial.isHidden=true}}
        }
    }
    @objc private func holdZoom(_ gesture:UILongPressGestureRecognizer){
        let point=gesture.location(in:view)
        switch gesture.state{
        case .began:zoomHoldStart=point;zoomHoldValue=zoom;showZoomDial()
        case .changed:setZoom(CameraZoom.drag(zoomHoldValue,delta:Double(point.x-zoomHoldStart.x),width:Double(view.bounds.width)))
        case .ended,.cancelled,.failed:hideZoomDialLater()
        default:break
        }
    }
    private func setZoom(_ value:Double){zoom=CameraZoom.clamp(value);engine.setZoom(zoom);dial.value=zoom;for b in zoomButtons{let selected=abs([1.0,2,3,6,120][b.tag]-zoom)<0.1;b.setTitleColor(selected ? orange : .white,for:.normal);b.backgroundColor=selected ? UIColor(white:0.15,alpha:1):.clear};if zoomButtons.allSatisfy({abs([1.0,2,3,6,120][$0.tag]-zoom)>0.1}){zoomButtons[0].setTitle(String(format:"%.1f×",zoom),for:.normal)}else{zoomButtons[0].setTitle("1×",for:.normal)}}
    @objc private func pinch(_ g:UIPinchGestureRecognizer){if g.state == .began{pinchStart=zoom;showZoomDial()};setZoom(pinchStart*Double(g.scale));if g.state == .ended || g.state == .cancelled{hideZoomDialLater()}}
    @objc private func flipCamera(){engine.chooseCamera(front:!state.front);setZoom(1)}
    @objc private func toggleFlash(){engine.toggleTorch();say(state.torch ? "Вспышка выкл." : "Вспышка вкл.")}
    @objc private func toggleStabilization(){options.horizon.toggle();options.crop = .fixed;engine.update(options);lastControls="";render();say(options.horizon ? "Сверхстабилизация включена" : "Сверхстабилизация выключена")}
    @objc private func centerFocus(){engine.focus(at:CGPoint(x:0.5,y:0.5));say("Автофокус по центру")}
    @objc private func tapFocus(_ gesture:UITapGestureRecognizer){let p=gesture.location(in:preview);engine.focus(at:CGPoint(x:p.y/max(1,preview.bounds.height),y:1-p.x/max(1,preview.bounds.width)));let marker=UIView(frame:CGRect(x:p.x-22,y:p.y-22,width:44,height:44));marker.isUserInteractionEnabled=false;marker.layer.borderWidth=1;marker.layer.borderColor=orange.cgColor;view.insertSubview(marker,belowSubview:toast);UIView.animate(withDuration:0.9,animations:{marker.alpha=0}){_ in marker.removeFromSuperview()}}
    @objc private func openExposure(){activeParameter="EV";slider.minimumValue = -2;slider.maximumValue=2;slider.value=0;slider.isHidden.toggle()}
    @objc private func parameter(_ b:UIButton){activeParameter=b.currentTitle ?? "EV";slider.isHidden=false;switch activeParameter{case "ISO":slider.minimumValue=50;slider.maximumValue=3200;slider.value=200;case "S":slider.minimumValue = -3;slider.maximumValue = -1;slider.value = -1.48;case "AF":slider.minimumValue=0;slider.maximumValue=1;slider.value=0.5;case "WB":slider.minimumValue=2000;slider.maximumValue=8000;slider.value=4000;default:slider.minimumValue = -2;slider.maximumValue=2;slider.value=0};view.setNeedsLayout()}
    @objc private func parameterChanged(){switch activeParameter{case "ISO":engine.setManual(iso:slider.value,seconds:nil,temperature:nil);case "S":engine.setManual(iso:nil,seconds:pow(10,Double(slider.value)),temperature:nil);case "AF":engine.setFocusDistance(slider.value);case "WB":engine.setManual(iso:nil,seconds:nil,temperature:slider.value);default:engine.setExposure(slider.value);exposure.setTitle(String(format:"EV %.1f",slider.value),for:.normal)};say("\(activeParameter): \(Int(slider.value))")}
    private func showPanel(_ title:String,_ choices:[(String,()->Void)]){
        dismissPanel();panelActions=choices.map{$0.1}
        let overlay=UIView(frame:view.bounds);overlay.autoresizingMask=[.flexibleWidth,.flexibleHeight]
        let shade=UIControl(frame:overlay.bounds);shade.autoresizingMask=[.flexibleWidth,.flexibleHeight];shade.backgroundColor=UIColor.black.withAlphaComponent(0.45);shade.addTarget(self,action:#selector(dismissPanel),for:.touchUpInside);overlay.addSubview(shade)
        let width=view.bounds.width-24,height=min(CGFloat(choices.count)*52+54,view.bounds.height-view.safeAreaInsets.top-90)
        let card=UIView(frame:CGRect(x:12,y:view.safeAreaInsets.top+50,width:width,height:height));card.backgroundColor=UIColor(white:0.1,alpha:0.98);card.layer.cornerRadius=20;card.clipsToBounds=true;overlay.addSubview(card)
        let label=UILabel(frame:CGRect(x:18,y:4,width:width-74,height:44));label.text=title;label.font = .systemFont(ofSize:15,weight:.semibold);label.textColor = .white;card.addSubview(label)
        let close=UIButton(type:.system);close.frame=CGRect(x:width-50,y:0,width:44,height:48);close.setTitle("×",for:.normal);close.titleLabel?.font = .systemFont(ofSize:25);close.tintColor = .white;close.addTarget(self,action:#selector(dismissPanel),for:.touchUpInside);card.addSubview(close)
        let scroll=UIScrollView(frame:CGRect(x:0,y:50,width:width,height:height-50));scroll.contentSize=CGSize(width:width,height:CGFloat(choices.count)*52);card.addSubview(scroll)
        for (i,item) in choices.enumerated(){let button=UIButton(type:.system);button.frame=CGRect(x:12,y:CGFloat(i)*52,width:width-24,height:48);button.tag=i;button.setTitle(item.0,for:.normal);button.titleLabel?.font = .systemFont(ofSize:13,weight:.medium);button.tintColor = .white;button.backgroundColor=UIColor(white:0.16,alpha:1);button.layer.cornerRadius=12;button.addTarget(self,action:#selector(panelChoice(_:)),for:.touchUpInside);scroll.addSubview(button)}
        panel=overlay;view.addSubview(overlay);overlay.alpha=0;card.transform=CGAffineTransform(translationX:0,y:-16)
        UIView.animate(withDuration:0.25,delay:0,options:[.beginFromCurrentState,.allowUserInteraction,.curveEaseOut],animations:{overlay.alpha=1;card.transform = .identity})
    }
    @objc private func panelChoice(_ button:UIButton){guard panelActions.indices.contains(button.tag) else{return};let action=panelActions[button.tag];dismissPanel();action()}
    @objc private func dismissPanel(){panel?.removeFromSuperview();panel=nil;panelActions=[]}
    @objc private func chooseFormat(){
        showPanel("Формат",["720·30","1080·30","4K·30","4K·60"].map{ value -> (String,()->Void) in (value,{[weak self] in self?.demoFormat=value;self?.format.setTitle(value,for:.normal)}) })
    }
    @objc private func openMenu(){
        showPanel("Параметры",[
            (options.horizon ? "Сверхстабилизация: выкл." : "Сверхстабилизация: вкл.",{[weak self] in self?.toggleStabilization()}),
            ("Сетка",{[weak self] in self?.preview.grid.toggle()}),
            ("Таймер: 2 с",{[weak self] in self?.say("2 с");DispatchQueue.main.asyncAfter(deadline:.now()+2){[weak self] in if self?.visible==true{self?.engine.stillFrame()}}}),
            ("Формат",{[weak self] in self?.chooseFormat()}),
            ("Галерея",{[weak self] in self?.openGallery()}),
            ("О записи",{[weak self] in self?.say("Основная камера: 1080p · 30 fps. 4K/60 — надписи для ролика.")})
        ])
    }
    private func openMore(){
        showPanel("Режимы",[
            ("Мастер",{[weak self] in guard let self=self else{return};self.mode=0;self.lastControls="";self.render()}),
            ("Видео",{[weak self] in guard let self=self else{return};self.changeMode(self.modeButtons[1])}),
            ("Фото",{[weak self] in guard let self=self else{return};self.changeMode(self.modeButtons[2])}),
            ("Портрет",{[weak self] in guard let self=self else{return};self.changeMode(self.modeButtons[3])}),
            ("Галерея",{[weak self] in self?.openGallery()})
        ])
    }
    @objc private func openGallery(){guard !state.recording && !state.finishing else{return};let library=LibraryViewController();library.theme=orange;let nav=UINavigationController(rootViewController:library);nav.modalPresentationStyle = .fullScreen;present(nav,animated:true)}
    @objc private func background(){engine.stop();preview.clear()}
    @objc private func foreground(){if visible && presentedViewController==nil{engine.start()}}
    private func say(_ text:String){toastTicket+=1;let ticket=toastTicket;toast.text=text;toast.alpha=1;DispatchQueue.main.asyncAfter(deadline:.now()+1.5){[weak self] in guard let self=self,self.toastTicket==ticket else{return};UIView.animate(withDuration:0.2){self.toast.alpha=0}}}
    #if targetEnvironment(simulator)
    func checkInterface()->[String]{
        loadViewIfNeeded();view.frame=CGRect(x:0,y:0,width:320,height:568);view.setNeedsLayout();view.layoutIfNeeded();var errors:[String]=[]
        for b in [flash,exposure,format,menu,gallery,flip,shutter]{if b.frame.width<44 || b.frame.height<44 || !view.bounds.contains(b.frame){errors.append("O2 touch target outside viewport")};if b.allTargets.isEmpty{errors.append("O2 button has no action")}}
        if options.resolution != 1080{errors.append("Real recording must stay 1080")}
        for b in zoomButtons{if !(b.gestureRecognizers ?? []).contains(where:{$0 is UILongPressGestureRecognizer}){errors.append("Hold zoom missing")}}
        if UIImage(named:"O2_menu") != nil && (menu.image(for:.normal)==nil || flip.image(for:.normal)==nil){errors.append("Artwork did not load")}
        setZoom(120);if zoom != 120{errors.append("O2 zoom")};setZoom(1)
        state.ready=false;state.recording=true;lastControls="";render();if !shutter.isEnabled{errors.append("Stop disabled when camera loses readiness")};state.ready=true;state.recording=false;lastControls="";render()
        format.sendActions(for:.touchUpInside);if panel==nil || presentedViewController != nil{errors.append("Format must open inside camera")};dismissPanel()
        menu.sendActions(for:.touchUpInside);if panelActions.count != 6{errors.append("Settings actions missing")};dismissPanel()
        for index in [0,1,2,3]{modeButtons[index].sendActions(for:.touchUpInside);if mode != index{errors.append("Mode does not switch")}}
        modeButtons[2].sendActions(for:.touchUpInside);return errors
    }
    func extraProbeImages(_ folder:URL){
        func shot(_ name:String){let image=UIGraphicsImageRenderer(bounds:view.bounds).image{context in view.layer.render(in:context.cgContext)};try? image.pngData()?.write(to:folder.appendingPathComponent(name))}
        openMenu();shot("settings-probe.png");dismissPanel();setZoom(3);showZoomDial();shot("zoom-probe.png");dial.isHidden=true;setZoom(1)
    }
    #endif
}

final class HorizonMapView:UIView{
    private let phone=CAShapeLayer(),crop=CAShapeLayer()
    override init(frame:CGRect){super.init(frame:frame);isUserInteractionEnabled=false;layer.addSublayer(phone);layer.addSublayer(crop);for s in [phone,crop]{s.fillColor=UIColor.clear.cgColor;s.lineWidth=1};phone.strokeColor=UIColor(white:1,alpha:0.6).cgColor;crop.strokeColor=UIColor.white.cgColor}
    required init?(coder:NSCoder){fatalError("init(coder:) is not used")}
    override func layoutSubviews(){super.layoutSubviews();CATransaction.begin();CATransaction.setDisableActions(true);phone.frame=bounds;crop.frame=bounds;phone.path=UIBezierPath(roundedRect:bounds.insetBy(dx:12,dy:10),cornerRadius:4).cgPath;let r=bounds.insetBy(dx:20,dy:22),p=UIBezierPath(rect:r);p.move(to:CGPoint(x:r.midX-4,y:r.midY));p.addLine(to:CGPoint(x:r.midX+4,y:r.midY));p.move(to:CGPoint(x:r.midX,y:r.midY-4));p.addLine(to:CGPoint(x:r.midX,y:r.midY+4));crop.path=p.cgPath;CATransaction.commit()}
    func setAngle(_ degrees:Double,ready:Bool){CATransaction.begin();CATransaction.setAnimationDuration(0.2);phone.transform=CATransform3DMakeRotation(CGFloat(degrees * .pi/180),0,0,1);crop.lineDashPattern=ready ? nil : [3,3];CATransaction.commit()}
}

private final class O2ZoomDial:UIView{
    var value=1.0{didSet{setNeedsDisplay()}}
    var onChange:((Double)->Void)?
    private var initial=1.0
    override init(frame:CGRect){super.init(frame:frame);backgroundColor = .clear;addGestureRecognizer(UIPanGestureRecognizer(target:self,action:#selector(pan(_:))))}
    required init?(coder:NSCoder){fatalError("init(coder:) is not used")}
    override func draw(_ rect:CGRect){guard let c=UIGraphicsGetCurrentContext() else{return};let center=CGPoint(x:bounds.midX,y:bounds.height+75),radius=bounds.width*0.54; c.setLineWidth(1);for tick in -35...35{let angle = -Double.pi/2+Double(tick)*0.021,major=tick%5==0,length:CGFloat=major ? 13:6;let p=CGPoint(x:center.x+CGFloat(cos(angle))*radius,y:center.y+CGFloat(sin(angle))*radius);let q=CGPoint(x:center.x+CGFloat(cos(angle))*(radius-length),y:center.y+CGFloat(sin(angle))*(radius-length));c.setStrokeColor(UIColor(white:major ? 0.9:0.35,alpha:1).cgColor);c.move(to:p);c.addLine(to:q);c.strokePath()};let text=String(format:"%.1f×",value) as NSString;text.draw(in:CGRect(x:bounds.midX-50,y:bounds.height-55,width:100,height:30),withAttributes:[.font:UIFont.monospacedDigitSystemFont(ofSize:16,weight:.semibold),.foregroundColor:UIColor.orange])}
    @objc private func pan(_ g:UIPanGestureRecognizer){if g.state == .began{initial=value};let changed=initial*pow(120,Double(g.translation(in:self).x)/Double(max(1,bounds.width)));onChange?(changed)}
}

#if targetEnvironment(simulator)
private enum CameraUIProbe {
    static func verifyRecordings(_ records:URL)throws->String{
        let size=CGSize(width:1080,height:1920)
        for round in 0..<3{
            let url=records.appendingPathComponent("Recording-check-\(UUID().uuidString).mov")
            let audio:[String:Any]? = round==1 ? [AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:44100,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:64000] : nil
            let recorder=try MovieRecorder(url:url,size:size,audioSettings:audio,context:CameraGPU.context)
            let frame=CIImage(color:CIColor(red:0.12,green:0.12,blue:0.12)).cropped(to:CGRect(origin:.zero,size:size))
            for i in 0..<15{
                for _ in 0..<100{recorder.append(image:frame,at:CMTime(value:Int64(i),timescale:30));if recorder.acceptedVideoFrames>i || recorder.failure != nil{break};Thread.sleep(forTimeInterval:0.01)}
            }
            let done=DispatchSemaphore(value:0);var outcome:Result<URL,Error>?
            recorder.finish{result in outcome=result;done.signal()}
            guard done.wait(timeout:.now()+15) == .success,let result=outcome else{throw CameraFailure.message("Stop did not complete")}
            switch result{case .failure(let error):throw error;case .success(let saved):
                let track=AVURLAsset(url:saved).tracks(withMediaType:.video).first
                guard track?.naturalSize==size,abs((track?.nominalFrameRate ?? 0)-30)<0.1,!FileManager.default.fileExists(atPath:saved.appendingPathExtension("recording").path) else{throw CameraFailure.message("Recording result invalid")}
            }
        }
        let empty=try MovieRecorder(url:records.appendingPathComponent("Empty-\(UUID().uuidString).mov"),size:size,audioSettings:nil,context:CameraGPU.context)
        var emptyFailed=false;empty.finish{result in if case .failure = result{emptyFailed=true}}
        guard emptyFailed else{throw CameraFailure.message("Empty stop must finish with an explicit error")}
        return "PASS three start/stop/save cycles 1080x1920 at 30 fps, including empty microphone input; empty video stop returns; simulator only"
    }
    static func run(_ window:UIWindow){
        DispatchQueue.main.asyncAfter(deadline:.now()+1){
            guard let root=window.rootViewController else{return}
            let errors: [String]
            if let camera=root as? CameraViewController{errors=camera.checkInterface()}
            else if let camera=root as? O2CameraViewController{errors=camera.checkInterface()}
            else{errors=["Unknown root controller"]}
            let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            if let result=NDDockRunChecks(){try? String(cString:result).write(to:folder.appendingPathComponent("dock-probe.txt"),atomically:true,encoding:.utf8)}
            let stamp=UILabel(frame:CGRect(x:0,y:root.view.bounds.height-14,width:root.view.bounds.width,height:14));stamp.text="UI-проверка · симулятор без камеры";stamp.textColor = .gray;stamp.font = .systemFont(ofSize:8);stamp.textAlignment = .center;root.view.addSubview(stamp)
            let renderer=UIGraphicsImageRenderer(bounds:root.view.bounds)
            let image=renderer.image{context in root.view.layer.render(in:context.cgContext)}
            try? image.pngData()?.write(to:folder.appendingPathComponent("ui-probe.png"))
            if let camera=root as? O2CameraViewController{camera.extraProbeImages(folder)}
            let library=LibraryViewController();library.loadViewIfNeeded();library.view.frame=CGRect(x:0,y:0,width:320,height:568);library.view.setNeedsLayout();library.view.layoutIfNeeded()
            let gallery=UIGraphicsImageRenderer(bounds:library.view.bounds).image{context in library.view.layer.render(in:context.cgContext)}
            try? gallery.pngData()?.write(to:folder.appendingPathComponent("gallery-probe.png"))
            try? (errors.isEmpty ? "PASS all controls have actions and fit 320x568; zoom works; simulator only\n" : errors.joined(separator:"\n")).write(to:folder.appendingPathComponent("ui-probe.txt"),atomically:true,encoding:.utf8)
            DispatchQueue.global(qos:.utility).async {
                do {
                    let records=try CameraEngine.library()
                    for i in 0..<4 {
                        let demo=UIGraphicsImageRenderer(size:CGSize(width:320,height:400)).image{context in UIColor(white:CGFloat(i+1)*0.18,alpha:1).setFill();context.fill(CGRect(x:0,y:0,width:320,height:400));("Тест галереи \(i+1)" as NSString).draw(at:CGPoint(x:40,y:180),withAttributes:[.font:UIFont.systemFont(ofSize:22),.foregroundColor:UIColor.white])}
                        try demo.jpegData(compressionQuality:0.85)?.write(to:records.appendingPathComponent("UI-test-\(i).jpg"))
                    }
                    let report=try verifyRecordings(records)
                    try report.write(to:folder.appendingPathComponent("video-probe.txt"),atomically:true,encoding:.utf8)
                    DispatchQueue.main.async {
                        let gallery=LibraryViewController();let nav=UINavigationController(rootViewController:gallery);nav.view.frame=CGRect(x:0,y:0,width:320,height:568);nav.loadViewIfNeeded();gallery.loadViewIfNeeded();nav.view.setNeedsLayout();nav.view.layoutIfNeeded()
                        DispatchQueue.main.asyncAfter(deadline:.now()+1){
                            let shot=UIGraphicsImageRenderer(bounds:nav.view.bounds).image{context in nav.view.layer.render(in:context.cgContext)}
                            try? shot.pngData()?.write(to:folder.appendingPathComponent("gallery-probe.png"))
                            try? "DONE".write(to:folder.appendingPathComponent("probe-done.txt"),atomically:true,encoding:.utf8)
                        }
                    }
                } catch {try? "FAIL \(error.localizedDescription)".write(to:folder.appendingPathComponent("video-probe.txt"),atomically:true,encoding:.utf8)}
            }
        }
    }
}
#endif
