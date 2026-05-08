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

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "道闸扫描"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        setupUI()
        requestPermission()
    }

    private func setupUI() {
        wifiLabel.text = "正在获取网络权限..."
        wifiLabel.font = .systemFont(ofSize: 22, weight: .bold)
        wifiLabel.translatesAutoresizingMaskIntoConstraints = false

        subnetLabel.font = .systemFont(ofSize: 13)
        subnetLabel.textColor = .secondaryLabel
        subnetLabel.numberOfLines = 2
        subnetLabel.translatesAutoresizingMaskIntoConstraints = false

        scanBtn.setTitle("开始扫描", for: .normal)
        scanBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        scanBtn.backgroundColor = .systemBlue
        scanBtn.setTitleColor(.white, for: .normal)
        scanBtn.layer.cornerRadius = 12
        scanBtn.addTarget(self, action: #selector(doScan), for: .touchUpInside)
        scanBtn.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = .systemGray5
        progressView.progressTintColor = .systemBlue

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false

        for v in [wifiLabel, subnetLabel, scanBtn, statusLabel, progressView, tableView] {
            view.addSubview(v)
        }

        NSLayoutConstraint.activate([
            wifiLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            wifiLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            wifiLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            subnetLabel.topAnchor.constraint(equalTo: wifiLabel.bottomAnchor, constant: 6),
            subnetLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            subnetLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scanBtn.topAnchor.constraint(equalTo: subnetLabel.bottomAnchor, constant: 20),
            scanBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scanBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scanBtn.heightAnchor.constraint(equalToConstant: 50),

            statusLabel.topAnchor.constraint(equalTo: scanBtn.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            progressView.heightAnchor.constraint(equalToConstant: 3),

            tableView.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 10),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: - Permission

    private func requestPermission() {
        // First get WiFi info (getifaddrs works without permission)
        let info = ScannerEngine.getWiFiInfo()

        if let ip = info.localIP {
            // Already have IP - try connecting to local gateway to trigger permission
            wifiLabel.text = ip
            subnetLabel.text = "正在请求本地网络权限..."
            triggerLocalNetworkPermission(info: info)
        } else {
            // No WiFi detected at all
            wifiLabel.text = "未检测到 WiFi"
            subnetLabel.text = "请连接 WiFi 后重试\n如已连接: 设置 → 隐私 → 本地网络 → 开启道闸扫描"
            scanBtn.isEnabled = true
            scanBtn.alpha = 1
        }
    }

    private func triggerLocalNetworkPermission(info: WiFiInfo) {
        // Try connecting to common local IPs to trigger the permission prompt
        let ips = Array(info.ipArray().prefix(10)) + ["192.168.1.1", "192.168.0.1", "10.0.0.1"]
        var tried = 0
        var gotResponse = false

        for ip in ips.prefix(5) {
            let conn = NWConnection(host: NWEndpoint.Host(ip), port: 80, using: .tcp)
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    conn.cancel()
                    if !gotResponse {
                        gotResponse = true
                        DispatchQueue.main.async { self?.refreshWiFi() }
                    }
                case .failed:
                    tried += 1
                    if tried >= 5 && !gotResponse {
                        gotResponse = true
                        DispatchQueue.main.async { self?.refreshWiFi() }
                    }
                default: break
                }
            }
            conn.start(queue: .global())
            // Cancel after 2s
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                conn.cancel()
                tried += 1
                if tried >= 5 && !gotResponse {
                    gotResponse = true
                    DispatchQueue.main.async { self?.refreshWiFi() }
                }
            }
        }

        // Fallback timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.wifiLabel.text == "正在请求本地网络权限..." || self?.subnetLabel.text == "正在请求本地网络权限..." {
                self?.refreshWiFi()
            }
        }
    }

    private func refreshWiFi() {
        let info = ScannerEngine.getWiFiInfo()
        if let ip = info.localIP {
            wifiLabel.text = ip
            let count = info.ipArray().count
            subnetLabel.text = "子网掩码: \(info.subnetMask ?? "---")\n待扫描: \(count) 个 IP × 8 端口"
            scanBtn.isEnabled = true
            scanBtn.alpha = 1
        } else {
            wifiLabel.text = "未获取到 WiFi 信息"
            subnetLabel.text = "请确认:\n1. 已连接 WiFi\n2. 已允许本地网络权限\n(设置 → 隐私 → 本地网络 → 道闸扫描)"
            scanBtn.isEnabled = true
            scanBtn.alpha = 1
        }
    }

    // MARK: - Scan

    @objc private func doScan() {
        let info = ScannerEngine.getWiFiInfo()
        guard info.localIP != nil else {
            let alert = UIAlertController(title: "无法扫描", message: "未检测到 WiFi 连接\n请到 设置 → 隐私 → 本地网络 中允许道闸扫描访问", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            present(alert, animated: true)
            return
        }

        results.removeAll()
        tableView.reloadData()
        scanBtn.isEnabled = false
        scanBtn.alpha = 0.5
        progressView.progress = 0
        statusLabel.text = "初始化扫描..."

        let eng = ScannerEngine()
        engine = eng

        eng.onResult = { [weak self] r in
            DispatchQueue.main.async {
                guard let self else { return }
                if let idx = self.results.firstIndex(where: { $0.ip == r.ip && $0.port == r.port }) {
                    self.results[idx] = r
                    self.tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
                } else {
                    self.results.append(r)
                    self.tableView.insertRows(at: [IndexPath(row: self.results.count-1, section: 0)], with: .automatic)
                }
            }
        }
        eng.onProgress = { [weak self] s, t in
            DispatchQueue.main.async {
                self?.progressView.progress = t > 0 ? Float(s)/Float(t) : 0
                self?.statusLabel.text = "扫描中: \(s) / \(t)"
            }
        }
        eng.onStatus = { [weak self] msg in
            DispatchQueue.main.async { self?.statusLabel.text = msg }
        }
        eng.onComplete = { [weak self] in
            DispatchQueue.main.async {
                self?.scanBtn.isEnabled = true
                self?.scanBtn.alpha = 1
                self?.progressView.progress = 1
                let online = self?.results.filter(\.reachable).count ?? 0
                let done = self?.results.filter({ $0.workingCred != nil }).count ?? 0
                self?.statusLabel.text = "完成: \(self?.results.count ?? 0) 服务, \(online) 在线, \(done) 可登录"
            }
        }
        eng.start()
    }
}

// MARK: - TableView

extension MainViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        let r = results[indexPath.row]
        var c = cell.defaultContentConfiguration()
        let icon = r.workingCred != nil ? "✅" : r.reachable ? "🔵" : "⬜"
        c.text = "\(icon) \(r.ip):\(r.port)  \(r.brand.name)"
        c.textProperties.font = .systemFont(ofSize: 14, weight: .medium)
        var detail = r.title
        if let cred = r.workingCred { detail = "密码: \(cred) | \(r.title)" }
        c.secondaryText = detail
        c.secondaryTextProperties.font = .systemFont(ofSize: 11)
        c.secondaryTextProperties.color = r.workingCred != nil ? .systemGreen : .secondaryLabel
        cell.contentConfiguration = c
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let r = results[indexPath.row]
        let alert = UIAlertController(title: "\(r.ip):\(r.port)", message: "品牌: \(r.brand.name)\n标题: \(r.title)\n密码: \(r.workingCred ?? "未破解")", preferredStyle: .actionSheet)
        if let cred = r.workingCred {
            alert.addAction(UIAlertAction(title: "复制密码 (\(cred))", style: .default) { _ in
                UIPasteboard.general.string = cred
            })
        }
        alert.addAction(UIAlertAction(title: "复制 IP:端口", style: .default) { _ in
            UIPasteboard.general.string = "\(r.ip):\(r.port)"
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = tableView.cellForRow(at: indexPath)
        }
        present(alert, animated: true)
    }
}
