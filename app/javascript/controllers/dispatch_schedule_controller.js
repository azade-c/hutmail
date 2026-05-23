import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cadence", "everyHours", "daily"]

  connect() {
    this.toggle()
  }

  toggle() {
    const cadence = this.cadenceTarget.value
    this.everyHoursTarget.hidden = cadence !== "every_hours"
    this.dailyTarget.hidden = cadence !== "daily"
  }
}
