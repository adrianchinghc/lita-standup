require 'mail'
require 'sucker_punch'
require 'sucker_punch/async_syntax'
require 'rufus-scheduler'

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
      ENV['MODE'] == 'test' ? dev_meth = ENV['MODE'] : dev_meth = :smtp
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
    redis.keys.each do |key|
      if key.to_s.include? response_prefix
        email_body += key.gsub(Date.parse(redis.get("last_standup_started_at")).strftime('%Y%m%d') + '-', "")
        email_body += "\n"
        email_body += MultiJson.load(redis.get(key)).join("\n")
        email_body += "\n"
      end
    end
    email_body
  end
end
