import SwiftUI

// MARK: - TableFieldView
struct TableFieldView: View {
    let field: FormField
    @Binding var responses: [String: String]
    
    @State private var tableData: [[String: Any]] = []
    
    private var columns: [TableColumn] { field.tableColumns ?? [] }
    private var isStaticMode: Bool { field.tableMode == "static" }
    private var staticRows: [StaticRow] { field.staticRows ?? [] }
    private var minRows: Int { field.minRows ?? 0 }
    private var maxRows: Int { field.maxRows ?? 100 }
    private var enableRowNames: Bool { field.enableRowNames ?? false }
    private var rowNameLabel: String { field.rowNameLabel ?? "Description" }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !columns.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    tableContent
                }
                
                if !isStaticMode && tableData.count < maxRows {
                    addRowButton
                }
                
                if isStaticMode && staticRows.isEmpty {
                    Text("No rows configured for this table")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No columns defined for this table field")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            loadExistingData()
        }
    }
    
    @ViewBuilder
    private var tableContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                if enableRowNames || isStaticMode {
                    Text(rowNameLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(minWidth: 120, alignment: .leading)
                        .padding(8)
                        .background(Color(.systemGray5))
                }
                
                ForEach(columns, id: \.id) { column in
                    Text(column.label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(minWidth: 120, alignment: .leading)
                        .padding(8)
                        .background(Color(.systemGray5))
                }
                
                if !isStaticMode {
                    Text("Actions")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 60)
                        .padding(8)
                        .background(Color(.systemGray5))
                }
            }
            .border(Color.gray.opacity(0.3), width: 1)
            
            // Data rows
            if displayRows.isEmpty {
                HStack {
                    Text(isStaticMode ? "No rows configured" : "No rows added yet. Tap 'Add Row' to get started.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                }
                .border(Color.gray.opacity(0.3), width: 1)
            } else {
                ForEach(Array(displayRows.enumerated()), id: \.offset) { index, row in
                    tableRow(row: row, rowIndex: index)
                }
            }
        }
    }
    
    @ViewBuilder
    private func tableRow(row: [String: Any], rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            // Row name column
            if enableRowNames || isStaticMode {
                if isStaticMode {
                    Text(row["_rowName"] as? String ?? staticRows.first(where: { $0.id == (row["_rowId"] as? String) })?.name ?? "")
                        .font(.caption)
                        .frame(minWidth: 120, alignment: .leading)
                        .padding(8)
                } else {
                    TextField(rowNameLabel, text: Binding(
                        get: { row["_rowName"] as? String ?? "" },
                        set: { updateCell(rowIndex: rowIndex, columnId: "_rowName", value: $0) }
                    ))
                    .font(.caption)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minWidth: 120)
                    .padding(4)
                }
            }
            
            // Data columns
            ForEach(columns, id: \.id) { column in
                cellView(column: column, rowIndex: rowIndex, row: row)
                    .frame(minWidth: 120)
                    .padding(4)
            }
            
            // Actions column
            if !isStaticMode {
                Button(action: {
                    removeRow(at: rowIndex)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                .frame(width: 60)
                .disabled(tableData.count <= minRows)
            }
        }
        .border(Color.gray.opacity(0.2), width: 1)
    }
    
    @ViewBuilder
    private func cellView(column: TableColumn, rowIndex: Int, row: [String: Any]) -> some View {
        let cellValue = row[column.id]
        
        switch column.type {
        case "text":
            TextField(column.label, text: Binding(
                get: { String(cellValue as? String ?? "") },
                set: { updateCell(rowIndex: rowIndex, columnId: column.id, value: $0) }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .font(.caption)
            
        case "number":
            TextField(column.label, text: Binding(
                get: {
                    if let num = cellValue as? Double {
                        return String(num)
                    } else if let num = cellValue as? Int {
                        return String(num)
                    }
                    return ""
                },
                set: { newValue in
                    if let num = Double(newValue), !newValue.isEmpty {
                        updateCell(rowIndex: rowIndex, columnId: column.id, value: num)
                    } else if newValue.isEmpty {
                        updateCell(rowIndex: rowIndex, columnId: column.id, value: 0)
                    }
                }
            ))
            .keyboardType(.decimalPad)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .font(.caption)
            
        case "date":
            let dateValue = parseDate(from: cellValue)
            DatePicker("", selection: Binding(
                get: { dateValue ?? Date() },
                set: { newDate in
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate]
                    updateCell(rowIndex: rowIndex, columnId: column.id, value: formatter.string(from: newDate))
                }
            ), displayedComponents: .date)
            .labelsHidden()
            .font(.caption)
            
        case "dropdown":
            Picker("", selection: Binding(
                get: { String(cellValue as? String ?? "") },
                set: { updateCell(rowIndex: rowIndex, columnId: column.id, value: $0) }
            )) {
                Text("Select").tag("")
                ForEach(column.options ?? [], id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .font(.caption)
            
        case "checkbox":
            Toggle("", isOn: Binding(
                get: { cellValue as? Bool ?? false },
                set: { updateCell(rowIndex: rowIndex, columnId: column.id, value: $0) }
            ))
            .labelsHidden()
            
        default:
            TextField(column.label, text: Binding(
                get: { String(describing: cellValue ?? "") },
                set: { updateCell(rowIndex: rowIndex, columnId: column.id, value: $0) }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .font(.caption)
        }
    }
    
    @ViewBuilder
    private var addRowButton: some View {
        Button(action: addRow) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add Row")
            }
            .font(.caption)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(BrandChrome.accent)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .disabled(tableData.count >= maxRows)
    }
    
    private var displayRows: [[String: Any]] {
        if isStaticMode && !staticRows.isEmpty {
            return staticRows.map { staticRow in
                if let existingRow = tableData.first(where: { ($0["_rowId"] as? String) == staticRow.id }) {
                    return existingRow
                } else {
                    var newRow: [String: Any] = ["_rowId": staticRow.id, "_rowName": staticRow.name]
                    columns.forEach { column in
                        newRow[column.id] = defaultValue(for: column.type)
                    }
                    return newRow
                }
            }
        }
        return tableData
    }
    
    private func defaultValue(for type: String) -> Any {
        switch type {
        case "number": return 0
        case "checkbox": return false
        default: return ""
        }
    }
    
    private func loadExistingData() {
        if let existingJson = responses[field.id], !existingJson.isEmpty {
            if let data = existingJson.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                tableData = decoded
            }
        }
        
        // Initialize static rows if needed
        if isStaticMode && !staticRows.isEmpty {
            let existingRowIds = Set(tableData.compactMap { $0["_rowId"] as? String })
            let missingRows = staticRows.filter { !existingRowIds.contains($0.id) }
            
            for staticRow in missingRows {
                var newRow: [String: Any] = ["_rowId": staticRow.id, "_rowName": staticRow.name]
                columns.forEach { column in
                    newRow[column.id] = defaultValue(for: column.type)
                }
                tableData.append(newRow)
            }
        }
        
        // Ensure minimum rows for dynamic mode
        if !isStaticMode {
            while tableData.count < minRows {
                addRow()
            }
        }
    }
    
    private func saveTableData() {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: tableData)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                responses[field.id] = jsonString
            }
        } catch {
            print("Failed to encode table data: \(error)")
        }
    }
    
    private func addRow() {
        guard tableData.count < maxRows else { return }
        
        var newRow: [String: Any] = [:]
        if enableRowNames {
            newRow["_rowName"] = ""
        }
        columns.forEach { column in
            newRow[column.id] = defaultValue(for: column.type)
        }
        tableData.append(newRow)
        saveTableData()
    }
    
    private func removeRow(at index: Int) {
        guard index < tableData.count, tableData.count > minRows else { return }
        tableData.remove(at: index)
        saveTableData()
    }
    
    private func updateCell(rowIndex: Int, columnId: String, value: Any) {
        // For static mode, find row by rowId
        if isStaticMode && rowIndex < displayRows.count {
            if let rowId = displayRows[rowIndex]["_rowId"] as? String {
                if let actualIndex = tableData.firstIndex(where: { ($0["_rowId"] as? String) == rowId }) {
                    tableData[actualIndex][columnId] = value
                    saveTableData()
                } else {
                    // Create new row with rowId
                    var newRow: [String: Any] = ["_rowId": rowId]
                    if let rowName = displayRows[rowIndex]["_rowName"] as? String {
                        newRow["_rowName"] = rowName
                    }
                    columns.forEach { column in
                        if newRow[column.id] == nil {
                            newRow[column.id] = defaultValue(for: column.type)
                        }
                    }
                    newRow[columnId] = value
                    tableData.append(newRow)
                    saveTableData()
                }
            }
        } else if rowIndex < tableData.count {
            tableData[rowIndex][columnId] = value
            saveTableData()
        }
    }
    
    private func parseDate(from value: Any?) -> Date? {
        guard let value = value else { return nil }
        
        if let dateString = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            // Try alternative formats
            let altFormatter = DateFormatter()
            altFormatter.dateFormat = "yyyy-MM-dd"
            return altFormatter.date(from: dateString)
        }
        
        return nil
    }
}
