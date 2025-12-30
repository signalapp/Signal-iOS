//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalServiceKit
import SignalUI

class InternalSQLClientViewController: UIViewController {

    let outputTextView: UITextView = {
        let textView = UITextView()
        textView.backgroundColor = .Signal.secondaryBackground
        textView.textColor = .Signal.secondaryLabel
        textView.text = "Output will appear here"
        textView.autocorrectionType = .no
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    let queryTextField: UITextField = {
        let textField = UITextField()
        textField.backgroundColor = .Signal.secondaryBackground
        textField.textColor = .Signal.secondaryLabel
        textField.font = .systemFont(ofSize: 16)
        textField.borderStyle = .roundedRect
        textField.placeholder = "Type your SQL query here"
        textField.autocorrectionType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    lazy var runQueryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Run Query", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 20)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(runQuery), for: .touchUpInside)
        return button
    }()

    lazy var copyOutputButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Copy Output", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 20)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(copyOutput), for: .touchUpInside)
        return button
    }()

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .Signal.background

        view.addSubview(outputTextView)
        view.addSubview(queryTextField)
        view.addSubview(runQueryButton)
        view.addSubview(copyOutputButton)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapView)))

        // Set up AutoLayout constraints
        NSLayoutConstraint.activate([
            copyOutputButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            copyOutputButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            copyOutputButton.heightAnchor.constraint(equalToConstant: 36),

            runQueryButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            runQueryButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            runQueryButton.heightAnchor.constraint(equalToConstant: 36),

            queryTextField.topAnchor.constraint(equalTo: runQueryButton.bottomAnchor, constant: 12),
            queryTextField.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            queryTextField.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            queryTextField.heightAnchor.constraint(equalToConstant: 48),

            outputTextView.topAnchor.constraint(equalTo: queryTextField.bottomAnchor, constant: 12),
            outputTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            outputTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            outputTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }

    @objc
    private func didTapView() {
        queryTextField.resignFirstResponder()
    }

    @objc
    private func runQuery() {
        queryTextField.resignFirstResponder()

        guard let query = queryTextField.text, !query.isEmpty else {
            return
        }

        let output = DependenciesBridge.shared.db.read { tx in
            let rows: [Row]
            do {
                rows = try Row.fetchAll(tx.database, sql: query)
            } catch let error {
                return "\(error)"
            }

            let rowStrings: [String] = rows.map { row in
                let columnValueStrings: [String] = row.map { (columnName: String, dbValue: DatabaseValue) -> String in
                    let valueString = switch dbValue.storage {
                    case .string(let string): string
                    case .int64(let int64): "\(int64)"
                    case .double(let double): "\(double)"
                    case .null: "NULL"
                    case .blob(let data): data.hexadecimalString
                    }

                    return "\(columnName):\(valueString)"
                }

                return "[\(columnValueStrings.joined(separator: ", "))]"
            }

            return rowStrings.joined(separator: "\n\n")
        }

        outputTextView.text = output
    }

    @objc
    private func copyOutput() {
        queryTextField.resignFirstResponder()
        guard let output = outputTextView.text, !output.isEmpty else {
            return
        }
        // Copy output text to clipboard
        UIPasteboard.general.string = output

        presentToast(text: "Copied!")
    }
}

// MARK: -

#if DEBUG

@available(iOS 17.0, *)
#Preview {
    InternalSQLClientViewController()
}

#endif
