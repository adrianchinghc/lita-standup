module Lita
  module Handlers
    class Standup < Handler
      # General settings
      config :time_to_respond, types: [Integer, Float], default: 60, required: true #minutes
      config :summary_email_recipients, type: Array, default: ['you@company.com'], required: true
      config :name_of_auth_group, type: Symbol, default: :standup_participants, required: true

      ## SMTP Mailer Settings ##
      config :address, type: String, required: true
      config :port, type: Integer, required: true
      config :domain, type: String, required: true
      config :user_name, type: String, required: true
      config :password, type: String, required: true
      config :authentication, type: String, required: true
      config :enable_starttls_auto, types: [TrueClass, FalseClass], required: true
      config :robot_email_address, type: String, default: 'noreply@lita.com', required: true
      config :email_subject_line, type: String, default: "Standup summary for --room-- --today--", required: true  #interpolated at runtime

      route %r{^start}i, :begin_standup, command: true, restrict_to: :standup_admins,
            help: { 'start' => 'start standup' }
      route %r{^list}i, :list_standups, command: true,
            help: { 'list' => 'show all standups' }
      route %r{response (1.*)(2.*)(3.*)}i, :process_standup, command: true

      def begin_standup(request)
        redis.set('last_standup_started_at', Time.now)
        redis.set('current_room', request.message.source.room)
        find_and_create_users
        message_all_users
        sec = config.time_to_respond * 60
        SummaryEmailJob.perform_in(sec, {redis: redis, config: config})
        one_day = (1439 - config.time_to_respond) * 60
        after(one_day) { |time| redis.keys.each{ |key| redis.del(key) } }
      end

      def process_standup(request)
        return unless timing_is_right?
        request.reply 'Response recorded. Thanks for partipating'
        date_string = Time.now.strftime('%Y%m%d')
        user_name = request.user.name
        redis.set(date_string + '-' + user_name, request.matches.first << redis.get('current_room'))
      end

      def list_standups(request)
        response_prefix = Date.parse(redis.get("last_standup_started_at")).strftime('%Y%m%d')
        standups = redis.keys.select do |key|
          (key.include? (response_prefix)) && (redis.get(key).include? (request.message.source.room))
        end
        if redis.get("last_standup_started_at") && standups.count > 0
          message = "Standups found: #{standups.count} \n"
          message << "Here they are: \n"
          standup = ''
          standups.each do |key|
            standup += key.gsub(response_prefix + '-', "")
            standup += "\n"
            *a, b = MultiJson.load(redis.get(key))
            standup += a.join("\n")
            standup += "\n"
          end
          message << standup
        else
          message = "No standups created yet. Use command: start"
        end
        request.reply message
      end

      private

      def message_all_users
        @users.each do |user|
          source = Lita::Source.new(user: user)
          robot.send_message(source, "Time for standup!")
          robot.send_message(source, render_template("instruction", robot: robot.name))
          robot.send_message(source, "Example: #{robot.name} response 1: Finished this gem. 2: Make these docs a little better. 3: Wife is making cookies and it's hard to focus.")
        end
      end

      def find_and_create_users
        @users ||= robot.auth.groups_with_users[config.name_of_auth_group]
      end

      def timing_is_right?
        return false unless redis.get('last_standup_started_at')
        intitiated_at = Time.parse(redis.get('last_standup_started_at'))
        return Time.now > intitiated_at && intitiated_at + (60*config.time_to_respond) > Time.now
      end

    end
    Lita.register_handler(Standup)
  end
end
