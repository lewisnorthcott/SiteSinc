import SwiftUI

struct ModernTableContent: View {
    let field: FormField
    let value: FormResponseValue?
    
    var body: some View {
        if let tableData = extractTableData(from: value) {
            if tableData.isEmpty {
                EmptyResponseView()
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    tableView(data: tableData)
                }
            }
        } else {
            EmptyResponseView()
        }
    }
    
    @ViewBuilder
    private func tableView(data: [[String: Any]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                if field.enableRowNames ?? false || field.tableMode == "static" {
                    Text(field.rowNameLabel ?? "Description")
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
            }
            .border(Color.gray.opacity(0.3), width: 1)
            
            // Data rows
            ForEach(Array(data.enumerated()), id: \.offset) { index, row in
                tableRow(row: row, rowIndex: index)
            }
        }
    }
    
    @ViewBuilder
    private func tableRow(row: [String: Any], rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            // Row name column
            if field.enableRowNames ?? false || field.tableMode == "static" {
                Text(getRowName(row: row, rowIndex: rowIndex))
                    .font(.caption)
                    .frame(minWidth: 120, alignment: .leading)
                    .padding(8)
            }
            
            // Data columns
            ForEach(columns, id: \.id) { column in
                let cellValue = row[column.id]
                Text(formatCellValue(cellValue, for: column.type))
                    .font(.caption)
                    .frame(minWidth: 120, alignment: .leading)
                    .padding(8)
            }
        }
        .border(Color.gray.opacity(0.2), width: 1)
    }
    
    private var columns: [TableColumn] {
        field.tableColumns ?? []
    }
    
    private func getRowName(row: [String: Any], rowIndex: Int) -> String {
        if let name = row["_rowName"] as? String, !name.isEmpty {
            return name
        } else if field.tableMode == "static", let rowId = row["_rowId"] as? String,
                let staticRow = field.staticRows?.first(where: { $0.id == rowId }) {
            return staticRow.name
        } else {
            return "Row \(rowIndex + 1)"
        }
    }
    
    private func extractTableData(from value: FormResponseValue?) -> [[String: Any]]? {
        guard let value = value else { return nil }
        
        // Try to extract as repeater (since backend might send it that way)
        if case .repeater(let repeaterData) = value {
            // Convert FormResponseValue dictionaries to [String: Any]
            return repeaterData.map { rowDict in
                rowDict.mapValues { formValue in
                    switch formValue {
                    case .string(let str): return str
                    case .int(let int): return int
                    case .double(let double): return double
                    case .stringArray(let arr): return arr
                    default: return String(describing: formValue)
                    }
                }
            }
        }
        
        // Try to extract as string (JSON string)
        if case .string(let jsonString) = value, !jsonString.isEmpty {
            if let data = jsonString.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return decoded
            }
        }
        
        return nil
    }
    
    private func formatCellValue(_ value: Any?, for type: String) -> String {
        guard let value = value else { return "-" }
        
        switch type {
        case "checkbox":
            if let boolValue = value as? Bool {
                return boolValue ? "Yes" : "No"
            }
            if let stringValue = value as? String {
                return (stringValue.lowercased() == "true" || stringValue == "1") ? "Yes" : "No"
            }
            return String(describing: value)
        case "number":
            if let num = value as? Double {
                return String(num)
            } else if let num = value as? Int {
                return String(num)
            }
            return String(describing: value)
        case "date":
            if let dateString = value as? String {
                // Try to format the date string
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
                if let date = formatter.date(from: dateString) {
                    let displayFormatter = DateFormatter()
                    displayFormatter.dateStyle = .medium
                    return displayFormatter.string(from: date)
                }
                return dateString
            }
            return String(describing: value)
        default:
            return String(describing: value)
        }
    }
}
