import UIKit
import AVKit
import Photos
import ImageIO

// A bounded thumbnail queue. Full photos and video frames are never decoded on the UI thread.
enum LibraryThumbnail {
    private static let cache = NSCache<NSString, UIImage>()
    private static let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .utility; return q }()
    static func load(url: URL, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        cache.totalCostLimit = 20 * 1024 * 1024; cache.countLimit = 80
        let key = (url.path + "-\(Int(size.width))x\(Int(size.height))") as NSString
        if let image = cache.object(forKey: key) { completion(image); return }
        queue.addOperation {
            var image: UIImage?
            autoreleasepool {
                if ["mov","mp4"].contains(url.pathExtension.lowercased()) {
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url)); generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: min(600, size.width * 2), height: min(600, size.height * 2))
                    if let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) { image = UIImage(cgImage: cg) }
                } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:min(1800,max(size.width,size.height)*2),kCGImageSourceShouldCacheImmediately:true]
                    if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) { image = UIImage(cgImage: cg) }
                }
            }
            if let image = image { cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4)) }
            DispatchQueue.main.async { completion(image) }
        }
    }
}
private struct LibraryItem { let url: URL; let created: Date; var video: Bool { ["mov","mp4"].contains(url.pathExtension.lowercased()) } }
private final class LibraryCell: UICollectionViewCell {
    let picture = UIImageView(), type = UILabel()
    var represented: URL?
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = UIColor(white:0.12,alpha:1)
        picture.contentMode = .scaleAspectFill; picture.clipsToBounds = true; contentView.addSubview(picture)
        type.font = .systemFont(ofSize:10,weight:.semibold); type.textColor = .white; type.backgroundColor = UIColor.black.withAlphaComponent(0.6); type.textAlignment = .center; contentView.addSubview(type)
        layer.cornerRadius = 8; clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func layoutSubviews() { super.layoutSubviews(); picture.frame = bounds; type.frame = CGRect(x:4,y:bounds.height-23,width:48,height:19) }
    override func prepareForReuse() { super.prepareForReuse(); represented = nil; picture.image = nil }
}
final class LibraryViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var theme = UIColor.white
    private let filters = UISegmentedControl(items: ["Все", "Фото", "Видео"])
    private let empty = UILabel()
    private var all: [LibraryItem] = [], shown: [LibraryItem] = []
    private lazy var collection: UICollectionView = {
        let layout = UICollectionViewFlowLayout(); layout.minimumInteritemSpacing = 5; layout.minimumLineSpacing = 5
        let view = UICollectionView(frame:.zero,collectionViewLayout:layout); view.backgroundColor = .black; view.dataSource = self; view.delegate = self; view.alwaysBounceVertical = true; return view
    }()
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Галерея"; view.backgroundColor = .black
        navigationController?.navigationBar.barStyle = .black; navigationController?.navigationBar.tintColor = theme
        navigationItem.leftBarButtonItem = UIBarButtonItem(title:"К камере",style:.plain,target:self,action:#selector(close))
        filters.tintColor = .white; filters.selectedSegmentIndex = 0; filters.addTarget(self,action:#selector(filter),for:.valueChanged)
        view.addSubview(filters); collection.register(LibraryCell.self,forCellWithReuseIdentifier:"media"); view.addSubview(collection)
        empty.text = "Здесь появятся фото и видео\nиз этой камеры"; empty.textColor = .lightGray; empty.textAlignment = .center; empty.numberOfLines = 2; view.addSubview(empty)
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let root = try? CameraEngine.library()
            let urls = root.flatMap { try? FileManager.default.contentsOfDirectory(at:$0,includingPropertiesForKeys:[.creationDateKey],options:[.skipsHiddenFiles]) } ?? []
            let items = urls.filter { ["jpg","jpeg","png","mov","mp4"].contains($0.pathExtension.lowercased()) }.map { LibraryItem(url:$0,created:(try? $0.resourceValues(forKeys:[.creationDateKey]))?.creationDate ?? .distantPast) }.sorted { $0.created > $1.created }
            DispatchQueue.main.async { self?.all = items; self?.filter() }
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); let safe = view.safeAreaInsets
        filters.frame = CGRect(x:16,y:safe.top+8,width:view.bounds.width-32,height:32)
        collection.frame = CGRect(x:10,y:filters.frame.maxY+12,width:view.bounds.width-20,height:max(0,view.bounds.height-safe.bottom-filters.frame.maxY-12))
        empty.frame = collection.frame; collection.collectionViewLayout.invalidateLayout()
    }
    @objc private func filter() { shown = all.filter { filters.selectedSegmentIndex == 0 || (filters.selectedSegmentIndex == 2) == $0.video }; empty.isHidden = !shown.isEmpty; collection.reloadData() }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { shown.count }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize { let side = floor((collectionView.bounds.width-10)/3); return CGSize(width:side,height:side*1.2) }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier:"media",for:indexPath) as! LibraryCell, item = shown[indexPath.item]
        cell.represented = item.url; cell.type.text = item.video ? "▶ Видео" : "Фото"
        LibraryThumbnail.load(url:item.url,size:CGSize(width:180,height:220)) { [weak cell] image in if cell?.represented == item.url { cell?.picture.image = image } }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) { navigationController?.pushViewController(MediaViewer(url:shown[indexPath.item].url),animated:true) }
    @objc private func close() { dismiss(animated:true) }
}
private final class MediaViewer: UIViewController, UIScrollViewDelegate {
    private let url: URL
    private let photo = UIImageView(), zoom = UIScrollView()
    private var player: AVPlayerViewController?
    init(url:URL) { self.url = url; super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        title = ["mov","mp4"].contains(url.pathExtension.lowercased()) ? "Видео" : "Фото"
        navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem:.action,target:self,action:#selector(share)),UIBarButtonItem(title:"В Фото",style:.plain,target:self,action:#selector(save))]
        if title == "Видео" {
            let controller = AVPlayerViewController(); controller.player = AVPlayer(url:url); player = controller
            addChild(controller); view.addSubview(controller.view); controller.didMove(toParent:self)
        } else {
            zoom.minimumZoomScale = 1; zoom.maximumZoomScale = 6; zoom.delegate = self; view.addSubview(zoom)
            photo.contentMode = .scaleAspectFit; zoom.addSubview(photo)
            let doubleTap = UITapGestureRecognizer(target:self,action:#selector(doubleTap(_:))); doubleTap.numberOfTapsRequired = 2; zoom.addGestureRecognizer(doubleTap)
            LibraryThumbnail.load(url:url,size:CGSize(width:900,height:1400)) { [weak self] image in self?.photo.image = image }
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); let safe = view.safeAreaInsets; let rect = view.bounds.inset(by:safe); player?.view.frame = rect; if zoom.zoomScale == 1 { zoom.frame = rect; photo.frame = zoom.bounds; zoom.contentSize = zoom.bounds.size } }
    override func viewDidAppear(_ animated:Bool) { super.viewDidAppear(animated); player?.player?.play() }
    override func viewWillDisappear(_ animated:Bool) { super.viewWillDisappear(animated); player?.player?.pause() }
    func viewForZooming(in scrollView:UIScrollView) -> UIView? { photo }
    @objc private func doubleTap(_ tap:UITapGestureRecognizer) { zoom.setZoomScale(zoom.zoomScale > 1 ? 1 : 3,animated:true) }
    @objc private func share() { let sheet = UIActivityViewController(activityItems:[url],applicationActivities:nil); sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first; present(sheet,animated:true) }
    @objc private func save() {
        PHPhotoLibrary.requestAuthorization { [weak self] permission in
            guard let self = self else { return }
            guard permission == .authorized else { self.message("Доступ к Фото не разрешён. Запись остаётся в галерее камеры."); return }
            PHPhotoLibrary.shared().performChanges({
                if ["mov","mp4"].contains(self.url.pathExtension.lowercased()) { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:self.url) }
                else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL:self.url) }
            }) { ok,error in self.message(ok ? "Сохранено в Фото" : error?.localizedDescription ?? "Не удалось сохранить") }
        }
    }
    private func message(_ text:String) { DispatchQueue.main.async { let alert = UIAlertController(title:nil,message:text,preferredStyle:.alert); alert.addAction(UIAlertAction(title:"ОК",style:.default)); self.present(alert,animated:true) } }
}
