module RIRC
  module ResponseTypes
    RESPONSE_CODE_MAPPING = YAML.load_file(File.join(File.dirname(__FILE__), '..', 'data', 'response_codes.yml'))
    RESPONSE_CLASSES = {}
    
    def self.create(response_string)
      details = parse_response_string_for_details(response_string)
      klass = RESPONSE_CLASSES[details[:name]] || Response
      klass.new(details)
    end
    
  private

    SENDER_AND_PARAMS_RE = /^:(.*?)\ (.*)/
    def self.parse_response_string_for_details(string)
      details = {}
      if md = SENDER_AND_PARAMS_RE.match(string)
        details[:sender_string] = md.captures[0]
        details[:string] = string
        return details.merge(parse_response_string_for_details(md.captures[1]))
      end
      details[:string] ||= string
      parts = string.split(' ', 2)
      name, code = (name = RESPONSE_CODE_MAPPING[parts[0]]) ? [name, parts[0]] : [parts[0], nil]
      details[:name], details[:code], details[:param_string] = name.downcase, code, parts[1]
      details
    end

    class Response
      attr_reader :sender_string, :code, :name, :param_string, :string
      
      def initialize(response_details = {})
        response_details.each { |k,v| instance_variable_set("@#{k}", v) }
      end
      
      def sender
        parse_sender_details!
        @sender
      end

      def trailing
        parse_params_and_trailing!
        @trailing
      end
      
      def params
        parse_params_and_trailing!
        @params
      end
      
    private
      TRAILING_AND_PARAMS_RE = /([^:]+)[:]?(.+)?/
      def parse_params_and_trailing!
        return nil if @params || @trailing
        if md = TRAILING_AND_PARAMS_RE.match(@param_string)
          @params = md.captures[0].split(' ')
          @trailing = md.captures[1]
        else
          @params, @trailing = [], ''
        end
      end
      
      SENDER_USER_RE = /(.*)!(.*)@(.*)/
      def parse_sender_details!
        return nil if @sender
        @sender = {:nick => nil, :user => nil, :host => nil}
        if md = SENDER_USER_RE.match(@sender_string)
          @sender[:nick], @sender[:user], @sender[:host] = md.captures
        else
          @sender[:host] = @sender_string
        end
      end
      
      PREDICATE_RE = /(.*?)\?$/
      def method_missing(sym, *args, &blk)
        if md = PREDICATE_RE.match(sym.to_s)
          md.captures[0] == @name
        else
          super
        end
      end
    
      def self.created_from(response_type)
        ResponseTypes::RESPONSE_CLASSES[response_type] = self
      end

    end
    
    class PrivateMessage < Response
      created_from 'privmsg'
      attr_reader :recipient, :message
      
      def initialize(*args)
        super
        @recipient, @message = params[0], @trailing
      end
      
      CHANNEL_STARTERS = [?&, ?#, ?+, ?!]
      def to_channel?
        CHANNEL_STARTERS.include?(recipient[0])
      end
      
      def to_user?
        !CHANNEL_STARTERS.include?(recipient[0])
      end
      
    end  
    
  end
  
end