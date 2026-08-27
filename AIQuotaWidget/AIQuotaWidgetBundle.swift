import SwiftUI
import WidgetKit

@main
struct AIQuotaWidgetBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 17.0, *) {
      AIQuotaInteractiveWidget()
    } else {
      AIQuotaWidget()
    }
  }
}
