import UIKit
import Network

final class MainViewController: UIViewController {
    private var results: [ScanResult] = []
    private var engine: ScannerEngine?

    private let wifiLabel = UILabel()
    private let subnetLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let tableView = UITableView()
    private let scanBtn = UIButton(type: .system)
    private let countLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "道闸扫描"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true

        setupUI()
        triggerNetworkPermission()
    }

    // MARK: - UI Layout (simple, reliable)

    private func setupUI() {
        // WiFi info
        wifiLabel.text = "正在获取网络信息..."
        wifiLabel.font = .systemFont(ofSize: 22, weight: .bold)
        wifiLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wifiLabel)

        subnetLabel.text = ""
        subnetLabel.font = .systemFont(ofSize: 13)
        subnetLabel.textColor = .secondaryLabel
        subnetLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subnetLabel)

        // Scan button
        scanBtn.setTitle("开始扫描", for: .normal)
        scanBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        scanBtn.backgroundColor = .systemBlue
        scanBtn.setTitleColor(.white, for: .normal)
        scanBtn.layer.cornerRadius = 12
        scanBtn.addTarget(self, action: #selector(doScan), for: .touchUpInside)
        scanBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanBtn)

        // Status
        statusLabel.text = ""
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // Progress
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = .systemGray5
        progressView.progressTintColor = .systemBlue
        view.addSubview(progressView)

        // Count
        countLabel.text = ""
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabel
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countLabel)

        // Table
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            wifiLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            wifiLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            wifiLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            subnetLabel.topAnchor.constraint(equalTo: wifiLabel.bottomAnchor, constant: 4),
            subnetLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            subnetLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scanBtn.topAnchor.constraint(equalTo: subnetLabel.bottomAnchor, constant: 20),
            scanBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scanBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scanBtn.heightAnchor.constraint(equalToConstant: 50),

            statusLabel.topAnchor.constraint(equalTo: scanBtn.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            countLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            countLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            tableView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 6),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: - Network Permission Trigger

    private func triggerNetworkPermission() {
        // NWBrowser triggers the "Local Network" permission prompt on iOS 14+
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: .tcp)
        var started = false
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if !started { started = true; browser.cancel() }
            case .failed:
                browser.cancel()
                // After permission (granted or denied), refresh WiFi info
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refreshWiFi() }
            case .cancelled:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refreshWiFi() }
            default: break
            }
        }
        browser.start(queue: .main)

        // Fallback: if browser doesn't trigger, still refresh after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.wifiLabel.text == "正在获取网络信息..." {
                self?.refreshWiFi()
            }
        }
    }

    private func refreshWiFi() {
        let info = ScannerEngine.getWiFiInfo()
        if let ip = info.localIP {
            wifiLabel.text = ip
            subnetLabel.text = "掩码: \(info.subnetMask ?? "---") | 扫描范围: \(info.ipArray().count) 个 IP"
        } else {
            wifiLabel.text = "未连接 WiFi"
            subnetLabel.text = "请先连接到 WiFi 网络"
        }
    }

    // MARK: - Scan

    @objc private func doScan() {
        results.removeAll()
        tableView.reloadData()
        scanBtn.isEnabled = false
        scanBtn.alpha = 0.5
        progressView.progress = 0

        let eng = ScannerEngine()
        engine = eng

        eng.onResult = { [weak self] r in
            guard let self else { return }
            if let idx = self.results.firstIndex(where: { $0.ip == r.ip && $0.port == r.port }) {
                self.results[idx] = r
                self.tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
            } else {
                self.results.append(r)
                self.tableView.insertRows(at: [IndexPath(row: self.results.count-1, section: 0)], with: .automatic)
            }
            self.updateCount()
        }
        eng.onProgress = { [weak self] s, t in
            self?.progressView.progress = t > 0 ? Float(s)/Float(t) : 0
            self?.statusLabel.text = "\(s) / \(t)"
        }
        eng.onStatus = { [weak self] s in self?.statusLabel.text = s }
        eng.onComplete = { [weak self] in
            self?.scanBtn.isEnabled = true
            self?.scanBtn.alpha = 1
            self?.progressView.progress = 1
        }
        eng.start()
    }

    private func updateCount() {
        let online = results.filter(\.reachable).count
        let done = results.filter { $0.workingCred != nil }.count
        countLabel.text = "发现 \(results.count) 个服务 | \(online) 在线 | \(done) 可登录"
    }
}

// MARK: - TableView

extension MainViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        let r = results[indexPath.row]
        var content = cell.defaultContentConfiguration()

        let icon = r.workingCred != nil ? "✅" : r.reachable ? "🔵" : "⬜"
        let portStr = r.port == 443 ? "https" : r.port == 80 ? "" : ":\(r.port)"
        let url = "\(portStr.isEmpty ? "":r.port == 80 ? "" : ":\(r.port)")"
        content.text = "\(icon) \(r.ip):\(r.port)  \(r.brand.name)"
        content.textProperties.font = .systemFont(ofSize: 14, weight: .medium)

        var detail = r.title
        if let cred = r.workingCred {
            detail = "密码: \(cred) | \(r.title)"
        }
        content.secondaryText = detail.isEmpty ? "" : detail
        content.secondaryTextProperties.font = .systemFont(ofSize: 11)
        content.secondaryTextProperties.color = r.workingCred != nil ? .systemGreen : .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let r = results[indexPath.row]
        let alert = UIAlertController(title: "\(r.ip):\(r.port)", message: "品牌: \(r.brand.name)\n标题: \(r.title)\n密码: \(r.workingCred ?? "未破解")", preferredStyle: .actionSheet)
        if let cred = r.workingCred {
            alert.addAction(UIAlertAction(title: "复制密码", style: .default) { _ in
                UIPasteboard.general.string = cred
            })
        }
        alert.addAction(UIAlertAction(title: "复制 IP", style: .default) { _ in
            UIPasteboard.general.string = "\(r.ip):\(r.port)"
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = tableView.cellForRow(at: indexPath)
        }
        present(alert, animated: true)
    }
}
