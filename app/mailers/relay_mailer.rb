class RelayMailer < ApplicationMailer
  def send_bundle(bundle)
    @bundle = bundle
    user = bundle.user

    mail(
      from: user.relay_smtp_username,
      to: user.sailmail_address,
      subject: "HUTMAIL #{Time.current.strftime('%d%b %H:%M').downcase}",
      body: bundle.bundle_text,
      content_type: "text/plain"
    )
  end
end
