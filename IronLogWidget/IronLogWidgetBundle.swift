import WidgetKit
import SwiftUI

@main
struct IronLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        RunLiveActivity()
    }
}
