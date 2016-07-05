require "spec_helper"

describe Lita::Handlers::Standup, lita_handler: true do
  it { is_expected.to route_command("start").with_authorization_for(:standup_admins).to(:begin_standup) }
  it { is_expected.to route_command("standup response 1:a2:b3:c").to(:process_standup) }


  before do
    @jimmy = Lita::User.create(111, name: "Jimmy")
    @tristan = Lita::User.create(112, name: "Tristan")
    @mitch = Lita::User.create(113, name: "Mitch")
    @test_room = Lita::Room.create_or_update("000_test@conf.hipchat.com")
    people = [@jimmy, @tristan, @mitch]
    registry.config.handlers.standup.time_to_respond =      60  #Not async for testing
    registry.config.handlers.standup.address =              'smtp.gmail.com'
    registry.config.handlers.standup.port =                 587
    registry.config.handlers.standup.domain =               'your.host.name'
    registry.config.handlers.standup.user_name =            ENV['USERNAME']
    registry.config.handlers.standup.password =             ENV['PASSWORD']
    registry.config.handlers.standup.authentication =       'plain'
    registry.config.handlers.standup.enable_starttls_auto = true
    people.each { |person| robot.auth.add_user_to_group!(person, :standup_participants) }
    people.each { |person| robot.auth.add_user_to_group!(person, :standup_admins) }
  end

  context '#begin_standup' do
    it 'messages each user and prompts for stand up options' do
      send_command("start", from: @test_room, as: @jimmy)
      expect(replies.size).to eq(9) #Jimmy, Tristan, and Mitch

    end

    it 'properly queues an email job upon initiation' do
      send_command("start", from: @test_room, as: @jimmy)
      send_command("response 1: everything 2:everything else 3:nothing", as: @jimmy)
      expect(SuckerPunch::Queue.all.first.name).to end_with("SummaryEmailJob")
    end
  end

  context '#process_standup' do
    it 'emails a compendium of responses out after users reply' do
      registry.config.handlers.standup.time_to_respond = (1.0/60.0)
      Timecop.freeze(Time.now) do
        send_command("start", from: @test_room, as: @jimmy)
        send_command("response 1: linguistics 2: more homework 3: being in seattle", as: @tristan)
        send_command("response 1: stitchfix 2: more stitchfix 3: gaining weight", as: @mitch)
        send_command("response 1: lita 2: Rust else 3: nothing", as: @jimmy)
      end
      Timecop.return
      sleep(2)
      expect(Mail::TestMailer.deliveries.last.body.raw_source).to include "Tristan\n1: linguistics \n2: more homework \n3: being in seattle\n"
      expect(Mail::TestMailer.deliveries.last.body.raw_source).to include "Jimmy\n1: lita \n2: Rust else \n3: nothing\n"
      expect(Mail::TestMailer.deliveries.last.body.raw_source).to include "Mitch\n1: stitchfix \n2: more stitchfix \n3: gaining weight\n"
    end
    it { should have_sent_email.with_subject("Standup summary for Test #{Time.now.strftime('%m/%d')}") }
  end

  # TO DO
  # Fix test + write test for list standups
end
