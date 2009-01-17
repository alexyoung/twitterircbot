module RIRC
  VERSION = '0.1'
  
  class Client
  
    attr_reader :connection
    attr_reader :options
    DEFAULT_OPTIONS = { :connection_class => Connection, 
                        :port => 6667,
                        :nickname => 'RIRCBot',
                        :username => 'rirc',
                        :realname => "RIRC Version #{RIRC::VERSION}",
                        :initial_mode_mask => 8 }
    
    def initialize(options = {})
      @options = DEFAULT_OPTIONS.merge(options)
      @connected = false
    end
  
    def connect!
      @connection = options[:connection_class].new(options[:server], options[:port])
      connection.connect
      start_loop
    end
    
    def quit!
      
    end
    
    def after_connect; end
    def before_response; end
    def after_response; end
    
    def after_disconnect
      puts "Disconnected."
    end
    
    def connected?
      @connected
    end

    def handle_namreply(response)
      puts response.trailing
    end
 
    def handle_motd(response)
      puts response.trailing
    end
    
    def disconnect!
      @connected = false
      @registered = false
      @nickname_registration_attempted = false      
    end
    
  private
    def register_with_server
      register_nickname
      register_user_details
    end
    
    def register_nickname
      connection.send.nick(options[:nickname]) unless @nickname_registration_attempted
      @nickname_registration_attempted = true
    end
    
    def register_user_details
      connection.send.user(options[:username], options[:initial_mode_mask], '*', ":#{options[:realname]}") unless @registered
      @registered = true
    end
    
    def start_loop
      while response = connection.read_response
        register_with_server unless connected?
        before_response
        handle_response(response)
        after_response
      end
    rescue EOFError, Timeout::Error => exception
      disconnect!
      after_disconnect
    end

    def handle_response(response)
      response_callback = "handle_#{response.name}"
      return nil if response_callback == 'handle_response' # Just in case of jerks.
      send(response_callback, response)
    rescue NoMethodError => exception
      puts "No handler for #{response.name} - #{response.string}"
    end
    
    def handle_welcome(response)
      @connected = true
      after_connect
    end
    
    def handle_ping(response)
      puts "PING? PONG!"
      connection.send.pong(response.params[0])
    end
    
  end
  
  class MessageLengthError < Exception; end
end
