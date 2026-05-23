class CommandResponseMailer < ApplicationMailer
  def send_response(command_response, auth_method: nil)
    @command_response = command_response
    vessel = command_response.vessel
    account = vessel.relay_account

    mail(
      from: account.smtp_username,
      to: vessel.sailmail_address,
      subject: "HUTMAIL #{command_response.command}",
      body: command_response.response_text,
      content_type: "text/plain",
      delivery_method_options: smtp_options_for(account, auth_method:)
    )
  end
end
