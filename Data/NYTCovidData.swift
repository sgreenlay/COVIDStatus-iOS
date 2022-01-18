
import Foundation
import Combine

import SwiftCSV
import GRDB

class CompletionHandler {
    var isCompleted: Bool { completed }
    
    private var completed: Bool = false
    private var completionHandler: () -> Void
    
    init(_ completion: @escaping () -> Void) {
        self.completionHandler = completion
    }
    
    func onCompleted() {
        self.completed = true
        self.completionHandler()
    }
}

class MultipleCompletionHandler {
    private var handlers: [CompletionHandler] = []
    private var completionHandler: (() -> Void)?
    
    func setHandler(_ completion: @escaping () -> Void) {
        self.completionHandler = completion
        self.checkHandlerCompleted()
    }
    
    func newHander() -> CompletionHandler {
        let handler = CompletionHandler(self.checkHandlerCompleted)
        handlers.append(handler)
        return handler
    }

    private func checkHandlerCompleted() {
        if handlers.first(where: { handler in !handler.isCompleted }) == nil {
            self.completionHandler?()
        }
    }
}

struct CovidDataFile: Codable, FetchableRecord, PersistableRecord {
    var id: String
    var lastUpdate: String
}

struct CovidCountyDataPoint: Codable, Identifiable, FetchableRecord, PersistableRecord {
    let id: String
    let date: String
    let geoid: String
    let county: String
    let state: String
    let cases: Int?
    let cases_avg: Float?
    let cases_avg_per_100k: Float?
    let deaths: Int?
    let deaths_avg: Float?
    let deaths_avg_per_100k: Float?
}

class CovidData {
    private var requests = Set<AnyCancellable>()
    
    private let files = [
        "us-counties-2020",
        "us-counties-2021"
    ]
    
    let dataDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.displayName!)
    
    func updateDbFromCSV(dbPool: DatabasePool, fileName: String, existingFile: CovidDataFile?, completion: @escaping () -> Void) {
        let commitRequest = GitHub.getLatestCommitForFile(author: "nytimes", repository: "covid-19-data", filePath: "rolling-averages/\(fileName).csv") { commit in
            
            if (existingFile != nil && existingFile!.lastUpdate == commit.commit.committer.date) {
                completion()
            } else {
                let fileRequest = GitHub.downloadFile(author: "nytimes", repository: "covid-19-data", filePath: "rolling-averages/\(fileName).csv") { tempFileURL in
                    DispatchQueue.global(qos: .background).async {
                        do {
                            try dbPool.write { db in
                                let tableExists = try db.tableExists("CovidCountyDataPoint")
                                if !tableExists {
                                    try db.create(table: "CovidCountyDataPoint") { t in
                                        t.column("id", .text).notNull()
                                        t.column("date", .text).notNull()
                                        t.column("geoid", .text).notNull()
                                        t.column("county", .text).notNull()
                                        t.column("state", .text).notNull()
                                        t.column("cases", .integer)
                                        t.column("cases_avg", .double)
                                        t.column("cases_avg_per_100k", .double)
                                        t.column("deaths", .integer)
                                        t.column("deaths_avg", .double)
                                        t.column("deaths_avg_per_100k", .double)
                                        t.primaryKey(["id"])
                                    }
                                }
                                let csvFile: CSV = try CSV(url: tempFileURL)
                                try csvFile.enumerateAsDict { row in
                                    do {
                                        let dataPoint = CovidCountyDataPoint(
                                            id: "\(row["date"]!)-\(row["geoid"]!)",
                                            date: row["date"]!,
                                            geoid: row["geoid"]!,
                                            county: row["county"]!,
                                            state: row["state"]!,
                                            cases: Int(row["cases"]!),
                                            cases_avg: Float(row["cases_avg"]!),
                                            cases_avg_per_100k: Float(row["cases_avg_per_100k"]!),
                                            deaths: Int(row["deaths"]!),
                                            deaths_avg: Float(row["deaths_avg"]!),
                                            deaths_avg_per_100k: Float(row["deaths_avg_per_100k"]!)
                                        )
                                        try dataPoint.save(db)
                                    } catch {
                                        print("Database error: \(error)")
                                    }
                                }
                                let updatedDataFile = CovidDataFile(id: fileName, lastUpdate: commit.commit.committer.date)
                                try updatedDataFile.save(db)
                            }
                        } catch {
                            print("Database error: \(error)")
                        }
                        DispatchQueue.main.async {
                            completion()
                        }
                    }
                }
                self.requests.insert(fileRequest)
            }
        }
        self.requests.insert(commitRequest)
    }
    
    func updateDb(completion: @escaping (DatabasePool) -> Void) {
        do {
            let dbUrl = self.dataDirectory.appendingPathComponent("database.sqlite")
            let dbPool = try DatabasePool(path: dbUrl.path)
            
            var processedFiles : [CovidDataFile]? = nil
            try dbPool.read { db in
                let tableExists = try db.tableExists("CovidDataFile")
                if !tableExists {
                    try dbPool.write { db in
                        try db.create(table: "CovidDataFile") { t in
                            t.column("id", .text).notNull()
                            t.column("lastUpdate", .text).notNull()
                            t.primaryKey(["id"])
                        }
                    }
                }
                processedFiles = try? CovidDataFile.fetchAll(db)
            }
            
            let completionHandler = MultipleCompletionHandler()
            for fileName in files {
                let processedFile = processedFiles?.first { $0.id == fileName }
                let handler = completionHandler.newHander()
                updateDbFromCSV(dbPool: dbPool, fileName: fileName, existingFile: processedFile, completion: handler.onCompleted)
            }
            completionHandler.setHandler {
                completion(dbPool)
            }
        } catch {
            print("Failed to update database: \(error)")
        }
    }
    
    func getForCounty(
        state: String,
        county: String,
        completion: @escaping ([CovidCountyDataPoint]) -> Void
    ) {
        getForCounty(state: state, county: county, latest: nil, completion: completion)
    }

    func getForCounty(
        state: String,
        county: String,
        latest: Int?,
        completion: @escaping ([CovidCountyDataPoint]) -> Void
    ) {
        self.updateDb { dbPool in
            do {
                try dbPool.read { db in
                    let countryData = try CovidCountyDataPoint.filter(
                        Column("state") == state &&
                        Column("county") == county
                    ).fetchAll(db).sorted(by: { $1.date > $0.date })
                    
                    if latest == nil {
                        completion(countryData)
                    } else {
                        completion(countryData.suffix(latest!))
                    }
                }
            } catch {
                print("Failed to query database: \(error)")
                completion([])
            }
        }
    }
}
