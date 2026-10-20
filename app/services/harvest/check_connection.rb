module Harvest
  # Confirms the token works and records who it belongs to and how the account
  # tracks time. Also fills in the matching person's Harvest user ID.
  class CheckConnection
    Outcome = Struct.new(:ok, :message, keyword_init: true)

    def self.call(client: Client.new, setting: LedgerSetting.current) = new(client, setting).call

    def initialize(client, setting)
      @client = client
      @setting = setting
    end

    def call
      company = @client.company
      me = @client.me
      name = [me["first_name"], me["last_name"]].compact_blank.join(" ")

      @setting.update!(
        harvest_account_name: company["name"],
        harvest_user_id: me["id"],
        harvest_user_name: name,
        harvest_user_email: me["email"],
        harvest_timestamp_mode: company["wants_timestamp_timers"] == true,
        harvest_checked_at: Time.current,
        harvest_check_error: nil
      )

      person = Person.find_by(email: me["email"].to_s.downcase)
      person.update!(harvest_user_id: me["id"]) if person && person.harvest_user_id.blank?

      message = "Connected to #{company['name']} as #{name}."
      message += " This account tracks start and end times, which this app can't send yet." if @setting.harvest_timestamp_mode
      Outcome.new(ok: !@setting.harvest_timestamp_mode, message:)
    rescue Client::Error => e
      @setting.update!(harvest_checked_at: Time.current, harvest_check_error: e.message)
      Outcome.new(ok: false, message: e.message)
    end
  end
end
