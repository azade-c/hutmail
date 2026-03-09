# Default dev user + vessel
if Rails.env.development?
  user = User.find_or_create_by!(email_address: "francois@hey.com") do |u|
    u.password = "francois"
    puts "🦫 Created dev user: francois@hey.com / francois"
  end

  vessel = Vessel.find_or_create_by!(callsign: "FX1234") do |v|
    v.sailmail_address = "fx1234@sailmail.com"
    v.daily_budget_kb = 200
    v.bundle_ratio = 80
    puts "🦫 Created dev vessel: FX1234"
  end

  Crew.find_or_create_by!(user: user, vessel: vessel) do |c|
    c.role = "captain"
    puts "🦫 Linked francois → FX1234 (skipper)"
  end
end
