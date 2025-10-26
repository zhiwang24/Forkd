import Foundation

//
//  NutrisliceService.swift
//
//  Created by Ayane on 10/26/25.
//

final class NutrisliceService {
    static let shared = NutrisliceService()
    private init() {}

    enum NutrisliceError: Error {
        case invalidURL
        case noData
        case httpError(status: Int)
        case parseError
    }

    /// Fetch menu items for a school. `district` is the subdomain (e.g. "techdining"),
    /// `school` is the slug used in the menu URL (e.g. "north-ave-dining-hall"),
    /// `meal` is typically "breakfast" or "lunch".
    func fetchMenu(district: String, school: String, meal: String, date: Date = Date(), debugDump: Bool = false) async throws -> [NutrisliceItem] {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { throw NutrisliceError.invalidURL }

        let urlString = "https://\(district).api.nutrislice.com/menu/api/weeks/school/\(school)/menu-type/\(meal)/\(year)/\(month)/\(day)/?format=json"
        guard let url = URL(string: urlString) else { throw NutrisliceError.invalidURL }

        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NutrisliceError.httpError(status: http.statusCode)
        }
        guard data.count > 0 else { throw NutrisliceError.noData }

        // If debugDump is enabled, attempt to pretty-print and save the raw JSON for inspection.
        if debugDump {
            do {
                let jsonObj = try JSONSerialization.jsonObject(with: data, options: [])
                let prettyData = try JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted])
                if let prettyString = String(data: prettyData, encoding: .utf8) {
                    print("[NutrisliceService] Raw JSON (pretty):\n\(prettyString)")
                }
                // write to temp file
                let tmp = NSTemporaryDirectory()
                let fileName = "nutrislice_\(district)_\(school)_\(meal)_\(year)-\(month)-\(day)_\(UUID().uuidString.prefix(8)).json"
                let url = URL(fileURLWithPath: tmp).appendingPathComponent(fileName)
                try prettyData.write(to: url)
                print("[NutrisliceService] Raw JSON written to: \(url.path)")
            } catch {
                print("[NutrisliceService] debugDump failed to serialize/write raw JSON: \(error)")
            }
        }

        // Try JSONSerialization and parse Nutrislice-specific "menu_items" structure.
        let json = try JSONSerialization.jsonObject(with: data, options: [])

        // Parsed items in order
        var parsed: [NutrisliceItem] = []

        func parseMenuItemsArray(_ arr: [Any]) {
            var currentStation = "Other"
            for case let obj as [String: Any] in arr {
                // If this element is a station header (section title), update currentStation
                if let isStationHeader = obj["is_station_header"] as? Bool, isStationHeader == true {
                    // Try `text` first, then `image_alt` as a fallback
                    if let text = obj["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        currentStation = text
                        continue
                    }
                    if let alt = obj["image_alt"] as? String, !alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        currentStation = alt
                        continue
                    }
                }
                if let isSectionTitle = obj["is_section_title"] as? Bool, isSectionTitle == true {
                    if let text = obj["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        currentStation = text
                        continue
                    }
                }

                // If the entry has a `food` object, it's a food item under the current station
                if let food = obj["food"] as? [String: Any] {
                    if let name = food["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // id preference: food.id, food.synced_id, fallback to dict id
                        let rawID = food["id"] ?? food["synced_id"] ?? obj["id"] ?? obj["menu_id"]
                        let idString: String
                        if let s = rawID as? String { idString = s }
                        else if let n = rawID as? NSNumber { idString = String(describing: n) }
                        else { idString = UUID().uuidString }

                        // category: use food.food_category if present and non-empty, else currentStation
                        let categoryCandidate = (food["food_category"] as? String)
                        let category = (categoryCandidate?.isEmpty ?? true) ? currentStation : categoryCandidate!

                        // extract labels/tags from food.icons.food_icons array
                        var labels: [String] = []
                        if let icons = food["icons"] as? [String: Any], let foodIcons = icons["food_icons"] as? [Any] {
                            for case let icon as [String: Any] in foodIcons {
                                if let name = icon["name"] as? String, !name.isEmpty {
                                    labels.append(name)
                                } else if let slug = icon["slug"] as? String, !slug.isEmpty {
                                    labels.append(slug)
                                }
                            }
                        }

                        let item = NutrisliceItem(id: idString, name: name, category: category, labels: labels)
                        parsed.append(item)
                        continue
                    }
                }

                // Some responses place item info at the top-level element
                if let name = obj["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // require an id or menu_id to avoid picking up unrelated name fields
                    if obj["menu_id"] != nil || obj["menuItemId"] != nil || obj["id"] != nil {
                        let rawID = obj["id"] ?? obj["menuItemId"] ?? obj["menu_id"]
                        let idString: String
                        if let s = rawID as? String { idString = s }
                        else if let n = rawID as? NSNumber { idString = String(describing: n) }
                        else { idString = UUID().uuidString }
                        let categoryCandidate = (obj["category"] as? String)
                        let category = (categoryCandidate?.isEmpty ?? true) ? currentStation : categoryCandidate!
                        let item = NutrisliceItem(id: idString, name: name, category: category, labels: [])
                        parsed.append(item)
                    }
                }
            }
        }

        // Try to locate `menu_items` in the response
        var found = false
        if let root = json as? [String: Any] {
            if let menuItems = root["menu_items"] as? [Any] {
                parseMenuItemsArray(menuItems)
                found = true
            } else {
                for (_, v) in root {
                    if let sub = v as? [String: Any], let menuItems = sub["menu_items"] as? [Any] {
                        parseMenuItemsArray(menuItems)
                        found = true
                        break
                    }
                    if let arr = v as? [Any] {
                        for case let el as [String: Any] in arr {
                            if let menuItems = el["menu_items"] as? [Any] {
                                parseMenuItemsArray(menuItems)
                                found = true
                                break
                            }
                        }
                        if found { break }
                    }
                }
            }
        }

        if !found {
            // Fallback: original tolerant walk to avoid returning empty results on unexpected shapes
            var bucket: [NutrisliceItem] = []
            func walk(_ node: Any) {
                if let arr = node as? [Any] {
                    for v in arr { walk(v) }
                } else if let dict = node as? [String: Any] {
                    if let name = dict["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let rawID = dict["id"] ?? dict["guid"] ?? dict["item_id"] ?? dict["menuItemId"]
                        let idString: String
                        if let s = rawID as? String { idString = s }
                        else if let n = rawID as? NSNumber { idString = String(describing: n) }
                        else { idString = UUID().uuidString }
                        let category = (dict["category"] as? String) ?? (dict["foodCategory"] as? String) ?? (dict["station"] as? String) ?? "Other"
                        let item = NutrisliceItem(id: idString, name: name, category: category, labels: [])
                        bucket.append(item)
                    }
                    for (_, v) in dict { walk(v) }
                }
            }
            walk(json)
            // dedupe
            var seen = Set<String>()
            let unique = bucket.filter { item in
                let key = "\(item.id)|\(item.name)"
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }
            return unique
        }

        // dedupe parsed
        var seen = Set<String>()
        let unique = parsed.filter { item in
            let key = "\(item.id)|\(item.name)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        return unique
    }
}

/// Minimal item representation returned by the Nutrislice service before mapping into the app's models.
struct NutrisliceItem: Identifiable {
    var id: String
    var name: String
    var category: String
    var labels: [String]
}
