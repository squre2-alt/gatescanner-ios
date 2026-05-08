import UIKit

final class MainViewController: UIViewController {
    private let engine = ScannerEngine()
    private var results: [ScanResult] = []

    // Header
    private let ipLabel = UILabel()
    private let maskLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressBar = UIProgressView(progressViewStyle: .bar)

    // Buttons
    private let scanBtn = UIButton(type: .system)
    private let stopBtn = UIButton(type: .system)

    // Results
    private let tableView = UITableView()
    private let countLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "道闸扫描"
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = true

        setupHeader()
        setupButtons()
        setupTable()
        setupCallbacks()
        updateWiFiDisplay()
    }

    // MARK: - Header

    private func setupHeader() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        func makeLabel(_ text: String, color: UIColor = .secondaryLabel) -> UILabel {
            let l = UILabel(); l.text = text; l.font = .systemFont(ofSize: 13); l.textColor = color; return l
        }

        ipLabel.font = .systemFont(ofSize: 24, weight: .bold)
        ipLabel.textColor = .label
        maskLabel.font = .systemFont(ofSize: 13)
        maskLabel.textColor = .secondaryLabel

        stack.addArrangedSubview(makeLabel("当前网络"))
        stack.addArrangedSubview(ipLabel)
        stack.addArrangedSubview(maskLabel)

        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Buttons

    private func setupButtons() {
        scanBtn.setTitle("开始扫描", for: .normal)
        scanBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        scanBtn.backgroundColor = .systemBlue
        scanBtn.setTitleColor(.white, for: .normal)
        scanBtn.layer.cornerRadius = 10
        scanBtn.addTarget(self, action: #selector(startScan), for: .touchUpInside)

        stopBtn.setTitle("停止", for: .normal)
        stopBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        stopBtn.backgroundColor = .systemRed
        stopBtn.setTitleColor(.white, for: .normal)
        stopBtn.layer.cornerRadius = 10
        stopBtn.isHidden = true
        stopBtn.addTarget(self, action: #selector(stopScan), for: .touchUpInside)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = ""
        statusLabel.textAlignment = .center

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.progress = 0
        progressBar.trackTintColor = .systemGray5
        progressBar.progressTintColor = .systemBlue

        let btnStack = UIStackView(arrangedSubviews: [scanBtn, stopBtn])
        btnStack.axis = .horizontal
        btnStack.spacing = 12
        btnStack.distribution = .fillEqually
        btnStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(btnStack)
        view.addSubview(statusLabel)
        view.addSubview(progressBar)

        NSLayoutConstraint.activate([
            btnStack.topAnchor.constraint(equalTo: maskLabel.bottomAnchor, constant: 20),
            btnStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            btnStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            btnStack.heightAnchor.constraint(equalToConstant: 44),

            statusLabel.topAnchor.constraint(equalTo: btnStack.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            progressBar.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Table

    private func setupTable() {
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabel
        countLabel.text = ""
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        tableView.register(ResultCell.self, forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

        view.addSubview(countLabel)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            countLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 10),
            countLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            tableView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 4),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        engine.onResult = { [weak self] r in
            guard let self else { return }
            // Update or insert
            if let idx = self.results.firstIndex(where: { $0.ip == r.ip && $0.port == r.port }) {
                self.results[idx] = r
                self.tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
            } else {
                self.results.append(r)
                self.tableView.insertRows(at: [IndexPath(row: self.results.count-1, section: 0)], with: .automatic)
            }
            self.updateCount()
        }
        engine.onProgress = { [weak self] s, t in
            self?.progressBar.progress = Float(s) / Float(t)
            self?.statusLabel.text = "\(s)/\(t)"
        }
        engine.onStatus = { [weak self] s in self?.statusLabel.text = s }
        engine.onComplete = { [weak self] in
            self?.scanBtn.isHidden = false
            self?.stopBtn.isHidden = true
            self?.progressBar.progress = 1
        }
    }

    // MARK: - Actions

    @objc private func startScan() {
        results.removeAll()
        tableView.reloadData()
        scanBtn.isHidden = true
        stopBtn.isHidden = false
        progressBar.progress = 0
        engine.start()
    }

    @objc private func stopScan() {
        engine.stop()
        scanBtn.isHidden = false
        stopBtn.isHidden = true
    }

    private func updateWiFiDisplay() {
        let info = engine.wifiInfo
        ipLabel.text = info.localIP ?? "未连接 WiFi"
        maskLabel.text = "子网掩码: \(info.subnetMask ?? "---")  |  扫描范围: \(info.ipArray().count) 个 IP"
    }

    private func updateCount() {
        let online = results.filter(\.reachable).count
        let cracked = results.filter { $0.workingCred != nil }.count
        countLabel.text = "共 \(results.count) 个设备 | \(online) 在线 | \(cracked) 可登录"
    }
}

// MARK: - UITableViewDataSource
extension MainViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! ResultCell
        cell.configure(results[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate
extension MainViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let r = results[indexPath.row]
        let vc = DetailViewController(result: r)
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - ResultCell

final class ResultCell: UITableViewCell {
    private let iconView = UIImageView()
    private let ipPortLabel = UILabel()
    private let brandLabel = UILabel()
    private let titleLabel = UILabel()
    private let credLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        iconView.tintColor = .systemGray
        iconView.contentMode = .scaleAspectFit

        ipPortLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        brandLabel.font = .systemFont(ofSize: 13)
        brandLabel.textColor = .secondaryLabel
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabel
        titleLabel.numberOfLines = 1
        credLabel.font = .systemFont(ofSize: 11, weight: .medium)
        credLabel.textColor = .systemGreen
        credLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [ipPortLabel, brandLabel, titleLabel, credLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let hStack = UIStackView(arrangedSubviews: [iconView, textStack])
        hStack.axis = .horizontal
        hStack.spacing = 12
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(hStack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            hStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ r: ScanResult) {
        ipPortLabel.text = "\(r.ip):\(r.port)"
        brandLabel.text = r.brand.name
        titleLabel.text = r.title.isEmpty ? "" : r.title
        credLabel.text = r.workingCred.map { "密码: \($0)" } ?? ""
        credLabel.isHidden = r.workingCred == nil
        iconView.image = UIImage(systemName: r.workingCred != nil ? "checkmark.shield.fill" : r.reachable ? "network" : "questionmark.circle")
        iconView.tintColor = r.workingCred != nil ? .systemGreen : r.reachable ? .systemBlue : .systemGray
    }
}

// MARK: - DetailViewController

final class DetailViewController: UIViewController {
    private let result: ScanResult

    init(result: ScanResult) { self.result = result; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = result.ip

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        func row(_ key: String, _ val: String) -> UIStackView {
            let k = UILabel(); k.text = key; k.font = .systemFont(ofSize: 13); k.textColor = .secondaryLabel; k.widthAnchor.constraint(equalToConstant: 80).isActive = true
            let v = UILabel(); v.text = val; v.font = .systemFont(ofSize: 14, weight: .medium); v.numberOfLines = 0; v.textColor = .label
            let s = UIStackView(arrangedSubviews: [k, v]); s.axis = .horizontal; s.spacing = 8; s.alignment = .top
            return s
        }

        stack.addArrangedSubview(row("IP 地址", result.ip))
        stack.addArrangedSubview(row("端口", "\(result.port)"))
        stack.addArrangedSubview(row("品牌", result.brand.name))
        stack.addArrangedSubview(row("标题", result.title.isEmpty ? "(无)" : result.title))
        stack.addArrangedSubview(row("服务器", result.server.isEmpty ? "(无)" : result.server))
        if let cred = result.workingCred {
            stack.addArrangedSubview(row("密码", cred))
        }
        stack.addArrangedSubview(row("状态", result.reachable ? "在线" : "离线"))
        stack.addArrangedSubview(UIView()) // spacer

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        // Copy button
        let copyBtn = UIButton(type: .system)
        copyBtn.setTitle("复制密码", for: .normal)
        copyBtn.addTarget(self, action: #selector(copyCred), for: .touchUpInside)
        copyBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(copyBtn)
        NSLayoutConstraint.activate([
            copyBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            copyBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            copyBtn.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @objc private func copyCred() {
        UIPasteboard.general.string = result.workingCred ?? "\(result.ip):\(result.port)"
        let a = UIAlertController(title: nil, message: "已复制", preferredStyle: .alert)
        present(a, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { a.dismiss(animated: true) }
    }
}
