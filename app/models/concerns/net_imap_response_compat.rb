require "net/imap"

# Tolerate malformed UIDPLUS response codes (RFC 4315) emitted by buggy IMAP
# servers — notably Mailo (mail.mailo.com), which returns COPYUID with
# uidvalidity=0 in violation of the nz-number grammar.
#
# Without this shim, net-imap's CopyUIDData constructor raises
# Net::IMAP::DataFormatError from inside the receiver thread, tearing down
# the TCP connection even though the COPY operation succeeded server-side.
# The follow-up uid_store +FLAGS \Deleted / uid_expunge then never executes,
# leaving messages duplicated in the source folder.
#
# By the time the inner constructor raises, all wire tokens up to the
# closing "]" have already been consumed, so swallowing the error and
# returning nil keeps the parser in sync. Callers see
# ResponseCode.new("COPYUID", nil) and the connection stays alive.
# Hutmail doesn't depend on the COPYUID source/dest UID mapping (we already
# know which UIDs we asked to copy/move), so we lose nothing functional.
#
# Same treatment for APPENDUID — same RFC, same potential server bug.
#
# This mirrors how Roundcube, K-9 Mail, and MailKit handle the same class
# of server bug: treat COPYUID/APPENDUID parse failures as non-fatal.
module NetImapResponseCompat
  def resp_code_copy__data
    super
  rescue Net::IMAP::DataFormatError => e
    Rails.logger.warn "net-imap: tolerating malformed COPYUID response (#{e.message})"
    nil
  end

  def resp_code_apnd__data
    super
  rescue Net::IMAP::DataFormatError => e
    Rails.logger.warn "net-imap: tolerating malformed APPENDUID response (#{e.message})"
    nil
  end
end
