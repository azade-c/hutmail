class RelayMailer < ApplicationMailer
  def send_bundle(bundle)
    @bundle = bundle
    vessel = bundle.vessel

    mail(
      from: vessel.relay_smtp_username,
      to: vessel.sailmail_address,
      subject: "HUTMAIL #{Time.current.strftime('%d%b %H:%M').downcase}",
      body: bundle.bundle_text,
      content_type: "text/plain"
    )
  end
end
