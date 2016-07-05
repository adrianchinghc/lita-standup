require 'mail'
require 'sucker_punch'
require 'sucker_punch/async_syntax'

class SummaryEmailJob
  include SuckerPunch::Job

  def perform(payload)
    redis = payload[:redis]
    config = payload[:config]

    email_body = build_email_body_from_redis(redis)
    options = { address:              config.address,
                port:                 config.port,
                domain:               config.domain,
                user_name:            config.user_name,
                password:             config.password,
                authentication:       config.authentication,
                enable_starttls_auto: config.enable_starttls_auto}

    Mail.defaults do
      ENV['MODE'] == 'test' ? dev_meth = :test : dev_meth = :smtp
      delivery_method(dev_meth , options)
    end

    if config.email_subject_line == "Standup summary for --room-- --today--"
      room_name = redis.get('current_room').split('@').first.split("_").drop(1).map(&:capitalize).join(" ")
      subject = config.email_subject_line.gsub(/--today--/, Time.now.strftime('%m/%d'))
      subject_line = subject.gsub(/--room--/, room_name)
    else
      subject_line = config.email_subject_line
    end

    mail = Mail.new do
      from    config.robot_email_address
      to      config.summary_email_recipients
      subject subject_line
      body    "#{email_body}"
    end

    if mail.deliver!
      Lita.logger.info("Sent standup email to #{mail.to} at #{Time.now}")
    end
  end

  def build_email_body_from_redis(redis)
    email_body = ''
    response_prefix = Date.parse(redis.get("last_standup_started_at")).strftime('%Y%m%d')
    standups = redis.keys.select do |key|
      (key.include? (response_prefix)) && (redis.get(key).include? (redis.get('current_room')))
    end
    standups.each do |key|
      email_body += key.gsub(response_prefix + '-', "")
      email_body += "\n"
      email_body += MultiJson.load(redis.get(key)).join("\n")
      email_body += "\n"
    end
    email_body
  end
end
