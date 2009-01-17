#!/usr/bin/env ruby 
require './init.rb'
require 'timeout'
gem 'twitter4r'
require 'twitter'
require 'ostruct'
require 'time'

BotConfig = OpenStruct.new(:server => 'irc.server.com',
  :owner => 'alex',
  :twitter => [
    OpenStruct.new(:login => 'username', :password => '')
  ]
)

Twitter::Client.configure do |conf|
  conf.protocol = :ssl
end

TwitterClients = BotConfig.twitter.collect do |config|
  Twitter::Client.new(:login => config.login, :password => config.password)
end

module TwitterHelpers
  def self.merged_timeline_for(timeline, options = {})
    options[:count] ||= 5
    strings = []
    TwitterClients.each do |client|
      client.timeline_for(timeline, options).each do |status|
        unless strings.find { |string| string[:id] == status.id }
          strings << {:id => status.id, :time => status.created_at, :text => self.status_text(client.send(:login), status)}
        end
      end
    end
    strings.sort { |a, b| b[:time] <=> a[:time] }.collect { |string| string[:text] }
  rescue Exception => e
    p e
  end

  def self.status_text(account, status)
    account_string = TwitterClients.size == 1 ? ' ' : " (#{account}) " 
    "#{status.created_at.strftime('%H:%M')}#{account_string}<#{status.user.screen_name}> #{status.text}"
  end

  def self.find_client(login)
    TwitterClients.find do |client|
      client.send(:login) == login
    end
  end

  def self.status(command, client, message)
    client.status command, message
  end
end

class Bot < RIRC::Client
  def after_connect
    options[:channel] = ARGV[1]
    process_pending_messages
    send_owner_recent_messages
    @client = TwitterClients.first
  end
  
  def handle_notice(response)
    puts response
  end
 
  def handle_unknowncommand(response)
    puts response
  end
 
  def handle_kill(response)
    @kill_count ||= 0
    @kill_count += 1  
    @pending_messages ||= []
    sleep 5
  end
  
  def after_disconnect
    @kill_count ||= 0
    connect! if @kill_count < 5
  end
  
  def process_pending_messages
    return nil unless @pending_messages && !@pending_messages.empty?
  end
 
  def handle_join(response)
    puts 'Joined'
  end

  def handle_topic(response)
    puts 'Topic'
  end
 
  def handle_namreply(response)
    @nicks = response.trailing.split(' ')
    @nicks.delete! options[:nickname]
  end

  def handle_privmsg(response)
    return unless response.sender[:nick] == BotConfig.owner
    
    return_strings = []

    if response.message =~ /^reload!$/
      return_strings << "Reloading..."
      $RELOADING = true 
      load __FILE__
      $RELOADING = false
    elsif response.message =~ /update/
      send_owner_recent_messages
      return
    elsif response.message =~ /^accounts/
      return_strings = return_strings | BotConfig.twitter.collect { |t| t.login }
    elsif response.message =~ /^account/
      message = response.message.sub(/^account/, '').strip
      if message.empty?
        return_strings << "Please enter an account name:"
        return_strings << BotConfig.twitter.collect { |t| t.login }
      else
        client = TwitterHelpers.find_client message
        if client
          @client = client
          return_strings << "Account set to: #{@client.send(:login)}"
        else
          return_strings << "Error: Account not found"
        end
      end
    elsif response.message =~ /^post/
      message = response.message.sub(/^post/, '').strip
      TwitterHelpers.status :post, @client, message
    end
  
    begin
      return_strings ||= [return_str]
      return_strings.each { |string| connection.send.privmsg(response.sender[:nick], ":#{string.strip}") }
    rescue RIRC::MessageLengthError => except
      return_strings = nil
      return_str = "HEY #{response.sender[:nick].upcase} THANKS FOR TRYING TO CRASH ME"
      retry
    end
  end
 
  def send_owner_recent_messages
    options = {}
    options[:since] = @last_update if @last_update
    return_strings = TwitterHelpers.merged_timeline_for(:friends, options)
    @last_update = Time.now
    return_strings.each { |string| connection.send.privmsg(BotConfig.owner, ":#{string.strip}") }
  end
end

unless $RELOADING
  bot = Bot.new(:server => BotConfig.server, :nickname => 'twitterirc', :username => 'irctwitter', :realname => 'Twitter IRC bot')

  twitter_thread = Thread.new(bot) do |bot|
    loop do
      bot.send_owner_recent_messages if bot.connected?
      sleep 60 * 5
    end
  end

  bot.connect!
  twitter_thread.join
end
