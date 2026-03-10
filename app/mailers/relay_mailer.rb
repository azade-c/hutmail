class RelayMailer < ApplicationMailer
  def send_bundle(bundle)
    @bundle = bundle
    vessel = bundle.vessel
    account = vessel.relay_account

    mail(
      from: account.smtp_username,
      to: vessel.sailmail_address,
      subject: "HUTMAIL #{Time.current.strftime('%d%b %H:%M').downcase}",
      body: bundle.bundle_text,
      content_type: "text/plain",
      delivery_method_options: smtp_options_for(account),
    )
  end
end
