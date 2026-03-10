class RelayMailer < ApplicationMailer
  def send_bundle(bundle)
    @bundle = bundle
    vessel = bundle.vessel

    mail(
      from: vessel.relay_smtp_username,
      to: vessel.sailmail_address,
      subject: "HUTMAIL #{Time.current.strftime('%d%b %H:%M').downcase}",
      body: bundle.bundle_text,
      content_type: "text/plain",
      delivery_method_options: smtp_options_for(vessel),
    )
  end

  private
    def smtp_options_for(vessel)
      {
        address: vessel.relay_smtp_server,
        port: vessel.relay_smtp_port,
        user_name: vessel.relay_smtp_username,
        password: vessel.relay_smtp_password,
        enable_starttls_auto: vessel.relay_smtp_use_starttls,
        authentication: :plain,
      }
    end
end
