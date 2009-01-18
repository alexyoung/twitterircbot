#!/usr/bin/env ruby 
require './init.rb'
require 'timeout'
begin
  gem 'mbbx6spp-twitter4r'
rescue
  puts "To get support for @replies, see:"
  puts "http://wiki.github.com/mbbx6spp/twitter4r/howto-install-github-development-releases"
  gem 'twitter4r'
end
require 'twitter'
require 'ostruct'
require 'time'

if ARGV[0]
  require ARGV[0]
else
  puts <<-TEXT
Run with an argument specifying the location of a configuration file in this format:

BotConfig = OpenStruct.new(:server => 'irc.server.com',
  :owner => 'alex',
  :twitter => [
    OpenStruct.new(:login => 'username', :password => '')
  ]
)

The configuration file format is ruby.
Specify as many twitter accounts as you like in an array.
  TEXT
  exit
end

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
      begin
      message = response.message.sub(/^post/, '').strip
      if message.nil? or message.size == 0
        return_strings << "Error: Please enter a status to post"
      elsif message.size > 140
        return_strings << "Error: Please enter a status shorter than 140 characters"
      else
        status = TwitterHelpers.status :post, @client, message
        return_strings << "Status posted: http://twitter.com/#{@client.send(:login)}/status/#{status.id}"
      end
      rescue Exception => e
        p e
      end
    elsif response.message =~ /^replies/
      puts "Getting replies"
      send_owner_recent_messages :replies
      return
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
 
  def send_owner_recent_messages(timeline = :friends)
    options = {}
    options[:since] = @last_update if @last_update
    return_strings = TwitterHelpers.merged_timeline_for(timeline, options)
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
