class MailboxesController < ApplicationController
  # GET /mailbox — unified bundle view across all accounts
  def show
    @mail_accounts = Current.user.mail_accounts.order(:name)

    if @mail_accounts.empty?
      @no_accounts = true
      return
    end

    # Fetch all accounts
    @accounts_with_emails = {}
    @fetch_errors = {}

    @mail_accounts.each do |account|
      result = ImapFetcher.new(account).fetch
      if result.success
        @accounts_with_emails[account] = result.emails
      else
        @fetch_errors[account] = result.error
        @accounts_with_emails[account] = []
      end
    end

    # Build the bundle (all emails from all accounts in one delivery)
    @bundle = SailmailComposer.bundle(@accounts_with_emails)

    # Process command if submitted
    if params[:command].present?
      @parse_result = CommandParser.parse(params[:command])
      if @parse_result.valid?
        @execution = CommandParser.execute(@parse_result.commands, message_count: @bundle[:message_count])

        # If DROP with specific indices, rebuild bundle without those messages
        if @execution[:drop_indices].any?
          filtered = filter_emails(@accounts_with_emails, @execution[:drop_indices])
          @bundle = SailmailComposer.bundle(filtered)
        end
      end
    end
  end

  private

  # Remove emails by global index across all accounts
  def filter_emails(accounts_with_emails, drop_indices)
    global_idx = 0
    filtered = {}

    accounts_with_emails.each do |account, emails|
      kept = []
      emails.each do |email|
        global_idx += 1
        kept << email unless drop_indices.include?(global_idx)
      end
      filtered[account] = kept
    end

    filtered
  end
end
