module RIRC    
  class Connection
    MAX_MESSAGE_LENGTH = 512
    attr_reader :server, :port
  
    class CommandProxy
      (public_instance_methods + private_instance_methods + protected_instance_methods).each do |method_name|
        define_method(method_name) { |*args| method_missing(method_name, *args) }
      end

      def initialize(connection)
        @connection = connection
      end

    private  

      def method_missing(sym, *args)
        @connection.write_command(sym.to_s, *args)
      end

    end # CommandProxy
    
    def initialize(server, port = 6667)
      @server = server
      @port = port
      @command_proxy = CommandProxy.new(self)
      @timeout = 300
    end
  
    def connect
      @socket = TCPSocket.new(@server, @port)
    end
  
    def disconnect
      @socket.close
      @socket = nil
    end
      
    def read
      timeout(@timeout) do
        @socket.readline.chomp
      end
    end
    
    def read_response
      ResponseTypes.create(self.read)
    end
    
    def write_command(type, *args)
      write("#{type} #{args.join(' ')}")
    end
    
    def write(message, add_line_endings = true)
      message = "#{message}\r\n" if add_line_endings
      raise MessageLengthError, "Maximum message length specified by the IRC protocol is #{MAX_MESSAGE_LENGTH} bytes." if message.size > MAX_MESSAGE_LENGTH
      timeout(@timeout) do
        @socket.write(message)
      end
    end
    
    def send
      @command_proxy
    end

  end
end
