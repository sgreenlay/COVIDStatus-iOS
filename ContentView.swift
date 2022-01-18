
import SwiftUI
import Charts
import Combine

struct ContentView: View {
    @State private var requests = Set<AnyCancellable>()
    @State private var data = CovidData()
    @State private var stateData = [CovidCountyDataPoint]()
    
    var normalizedData: (dates: [String], cases: [Float], averageCases: [Float]) {
        let validData = stateData.filter { dataPoint in dataPoint.cases != nil }
        
        let cases = validData.map { max(Float($0.cases!), 0.0) }
        let averageCases = validData.map { Float($0.cases_avg!) }
        
        let dataPointsMax = max(cases.max()!, averageCases.max()!)
        
        return (
            dates: validData.map { dataPoint in dataPoint.date },
            cases: cases.map { dataPoint in dataPoint / dataPointsMax },
            averageCases: averageCases.map { dataPoint in dataPoint / dataPointsMax }
        )
    }
    
    var body: some View {
        VStack {
            if stateData.isEmpty {
                ProgressView().padding()
                Text("Retrieving latest data...")
            } else {
                let data = normalizedData
                ZStack {
                    Chart(data: data.cases)
                        .chartStyle(
                            ColumnChartStyle(column: Rectangle().foregroundColor(.red.opacity(0.4)), spacing: 0)
                        )
                    Chart(data: data.averageCases)
                        .chartStyle(
                            LineChartStyle(.quadCurve, lineColor: .red, lineWidth: 2.0)
                        )
                }.padding()
            }
        }.onAppear(perform: fetchData)
    }
    
    private func fetchData() {
        data.getForCounty(state: "Washington", county: "King") { data in
            stateData = data
        }
    }
}
