import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["imapEncryption", "imapPort", "smtpEncryption", "smtpPort"]

  static values = {
    imapPorts: { type: Object, default: { ssl: 993, starttls: 143, none: 143 } },
    smtpPorts: { type: Object, default: { ssl: 465, starttls: 587, none: 25 } }
  }

  imapEncryptionChanged() {
    const mode = this.imapEncryptionTarget.value
    this.imapPortTarget.value = this.imapPortsValue[mode] || 993
  }

  smtpEncryptionChanged() {
    const mode = this.smtpEncryptionTarget.value
    this.smtpPortTarget.value = this.smtpPortsValue[mode] || 465
  }
}
