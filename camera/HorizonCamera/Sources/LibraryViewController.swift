import UIKit
import AVKit
import Photos
import ObjectiveC

final class LibraryViewController: UITableViewController {
    var theme = UIColor.yellow
    private var files: [URL] = []
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Записи"; view.backgroundColor = .black
        navigationController?.navigationBar.barStyle = .black; navigationController?.navigationBar.tintColor = theme
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "К камере", style: .plain, target: self, action: #selector(close))
        if let root = try? CameraEngine.library(), let all = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) {
            files = all.filter { ["mov", "jpg"].contains($0.pathExtension) }.sorted { date($0) > date($1) }
        }
        if files.isEmpty { let label = UILabel(); label.text = "Записи появятся здесь"; label.textColor = .lightGray; label.textAlignment = .center; tableView.backgroundView = label }
    }
    private func date(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { files.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil), url = files[indexPath.row]
        cell.backgroundColor = UIColor(white: 0.07, alpha: 1); cell.textLabel?.textColor = .white; cell.detailTextLabel?.textColor = .lightGray
        cell.textLabel?.text = url.pathExtension == "mov" ? "Видео" : "Стоп-кадр"
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        cell.detailTextLabel?.text = formatter.string(from: date(url)); cell.accessoryType = .disclosureIndicator; return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let url = files[indexPath.row]
        let viewer: UIViewController
        if url.pathExtension == "mov" { let player = AVPlayerViewController(); player.player = AVPlayer(url: url); viewer = player; player.player?.play() }
        else { viewer = UIViewController(); viewer.view.backgroundColor = .black; let image = UIImageView(image: UIImage(contentsOfFile: url.path)); image.contentMode = .scaleAspectFit; image.frame = viewer.view.bounds; image.autoresizingMask = [.flexibleWidth, .flexibleHeight]; viewer.view.addSubview(image) }
        let actions = AssetActions(url: url, presenter: viewer); objc_setAssociatedObject(viewer, &assetActionsKey, actions, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        viewer.navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .action, target: actions, action: #selector(AssetActions.share)), UIBarButtonItem(title: "В Фото", style: .plain, target: actions, action: #selector(AssetActions.save))]
        navigationController?.pushViewController(viewer, animated: true)
    }
    @objc private func close() { dismiss(animated: true) }
}
private var assetActionsKey: UInt8 = 0
private final class AssetActions: NSObject {
    let url: URL; weak var presenter: UIViewController?
    init(url: URL, presenter: UIViewController) { self.url = url; self.presenter = presenter }
    @objc func share() {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = presenter?.navigationItem.rightBarButtonItems?.first
        presenter?.present(activity, animated: true)
    }
    @objc func save() {
        let perform: (PHAuthorizationStatus) -> Void = { status in
            guard status == .authorized else { self.message("Доступ к Фото не разрешён. Файл остался в приложении."); return }
            PHPhotoLibrary.shared().performChanges({
                if self.url.pathExtension == "mov" { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.url) }
                else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: self.url) }
            }) { saved, error in self.message(saved ? "Сохранено в Фото" : (error?.localizedDescription ?? "Сохранить не удалось")) }
        }
        if #available(iOS 14.0, *) { PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: perform) }
        else { PHPhotoLibrary.requestAuthorization(perform) }
    }
    private func message(_ text: String) { DispatchQueue.main.async { let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert); alert.addAction(UIAlertAction(title: "ОК", style: .default)); self.presenter?.present(alert, animated: true) } }
}
