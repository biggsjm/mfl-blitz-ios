import SwiftUI

struct LeagueScheduleView: View {
    var body: some View {
        ScheduleTimeline(franchiseID: nil)
            .navigationTitle("Season schedule")
            .navigationBarTitleDisplayMode(.inline)
    }
}
