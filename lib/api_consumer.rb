class APIConsumer
  require 'yaml'
  require 'net/https'
  require 'uri'
  require 'json'
  require 'uber_cache'
  require 'logger'

  class << self
    @settings = {}
    def inherited(subclass)
      if File.exist?("config/#{snake_case(subclass)}.yml")
        configs = YAML.load_file("config/#{snake_case(subclass)}.yml")
        configs[snake_case(subclass)].each{ |k,v| subclass.set(k.to_sym, v) }
        subclass.set_logger(Logger.new(subclass.settings[:log_file] || "./log/#{snake_case(subclass)}_api.log"), subclass.settings[:log_level])
        super
      else
        raise RuntimeError, "Please create config file: 'config/#{snake_case(subclass)}.yml'"
      end
    end
    
    def set_logger(logger, level=nil)
      @logger = logger.nil? ? Logger.new(STDERR) : logger
      set_log_level(level)
    end
    
    def log
      @logger
    end
    
    def set_log_level(level=nil)
      if level.nil?
        level = if([nil, "development", "test"].include?(ENV['RACK_ENV']))
          :info
        else
          :warn
        end
      end
      @logger.level = case level.to_sym
      when :debug
        Logger::DEBUG
      when :info
        Logger::INFO
      when :error
        Logger::ERROR
      when :fatal
        Logger::FATAL
      else #warn
        Logger::WARN
      end
    end
    
    def memcache?
      settings[:use_memcache]
    end
    
    def memcache_hosts
      settings[:memcache_hosts]
    end

    def set(key, val)
      settings[key] = val
    end

    def settings
      @settings ||= {}
    end
    
    DEFAULT_REQUEST_OPTS = {
      :method => :get,
      :headers => {
        "Accept" => "application/json",
        "Content-Type" => "application/json",
        "User-Agent" => "API-CONSUMER-#{ENV['RACK_ENV'] || 'dev'}"
      },
      :ttl => 300
    }
    def do_request(path, conn, opts = {}, &blk)
      if(opts[:verbose])
        log.debug("Sending request to: #{conn.address}#{':' + conn.port.to_s if conn.port}#{path}")
      end
      if opts[:key] # cache if key sent
        read_val = nil
        return read_val if !opts[:reload] && read_val = cache.obj_read(opts[:key])
        opts[:ttl] ||= settings[:ttl] || DEFAULT_REQUEST_OPTS[:ttl]
      end
      opts[:headers] = DEFAULT_REQUEST_OPTS[:headers].merge(opts[:headers] || {})
      opts[:method] = opts[:method] || DEFAULT_REQUEST_OPTS[:method]

      path = decorate_path( path )
      req = if( opts[:method] == :get)
        Net::HTTP::Get.new(path)
      elsif( opts[:method] == :post)
        Net::HTTP::Post.new(path)
      elsif( opts[:method] == :delete)
        Net::HTTP::Delete.new(path)
      elsif( opts[:method] == :put)
        Net::HTTP::Put.new(path)
      else
        log.error "BUG - method=>(#{opts[:method]})"
      end
      opts[:headers].each { |k,v| req[k] = v }
      settings[:headers].each { |k,v| req[k] = v } if settings[:headers]
      req.basic_auth settings[:api_user], settings[:api_password] if settings[:api_user] && settings[:api_password]
      #req["connection"] = 'keep-alive'
      req.body = opts[:body] if opts[:body]

      response = nil
      begin
        log.debug "CONN:" + conn.inspect
        log.debug "REQ:" + req.inspect
        response = conn.request(req)
        
        results = JSON.parse(response.body)
        accept_codes = [200, 201, 202]
        accept_codes += settings[:accept_codes].map(&:to_i) if settings[:accept_codes]
        if ![200, 201].include?(response.code.to_i)
          results = error_code(response.code, opts[:errors], results)
        end
        results = blk.call(results) if blk
        cache.obj_write(opts[:key], results, :ttl => opts[:ttl]) if opts[:key]
        return results
      rescue Exception => exception
        log.error exception.message
        log.error exception.backtrace        
        return error_code(response ? response.code : "NO CODE" , opts[:errors])
      end
      data = response.body
      data = blk.call(data) if blk
      cache.obj_write(opts[:key], data, :ttl => opts[:ttl]) if opts[:key]
      return data
    end
    
    def connection(connection_flag = :normal)
      @connections ||= {}
      return @connections[connection_flag] if @connections[connection_flag]
      @connections[connection_flag] = create_connection
    end
    
    def create_connection(debug = false)
      if @uri.nil? || @uri.port.nil?
        log.info "CONNECTING TO: #{settings[:url]}"
        @uri = URI.parse("#{settings[:url]}/")
      end
      http = Net::HTTP.new(@uri.host, @uri.port)
      if settings[:ssl] == true
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      http.set_debug_output $stderr if debug
      http.open_timeout = 7
      http.read_timeout = 15
      http
    end

    def cache
      @cache ||= UberCache.new(settings[:cache_prefix], settings[:memcache_hosts])
    end

    private
    def snake_case(camel_cased_word)
      camel_cased_word.to_s.gsub(/::/, '_').
      gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
      gsub(/([a-z\d])([A-Z])/,'\1_\2').
      tr("-", "_").
      downcase
    end
    
    def error_code(code, errors = nil, response = nil)
      ret_val = {:error => true, :message => (errors && errors[code.to_s] ? errors[code.to_s] : "API error: #{code}" )}
      ret_val[:response] = response if response
      return ret_val
    end

    def decorate_path(p)
      p
    end
  end
end
