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

  private
    def smtp_options_for(account)
      options = {
        address: account.smtp_server,
        port: account.smtp_port,
        enable_starttls_auto: account.smtp_use_starttls
      }

      if account.smtp_username.present?
        options[:user_name] = account.smtp_username
        options[:password] = account.smtp_password
        options[:authentication] = :plain
      end

      options
    end
end
