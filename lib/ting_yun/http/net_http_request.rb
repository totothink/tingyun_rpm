require 'ting_yun/http/abstract_request'
module TingYun
  module Http
    class NetHttpRequest < AbstractRequest
      def initialize(connection, request)
        @connection = connection
        @request = request
      end

      def type
        @connection.use_ssl? ? 'https' : 'http'
      end

      def from
        "net http"
      end

      def host
        if hostname = self['host']
          hostname.split(':').first
        else
          @connection.address
        end
      end

      def port
        @connection.port
      end

      def method
        @request.method
      end

      def [](key)
        @request[key]
      end

      def []=(key, value)
        @request[key] = value
      end

      def path
        @request.path
      end

      def uri
        case @request.path
          when /^https?:\/\//
            URI(@request.path)
          else
            scheme = @connection.use_ssl? ? 'https' : 'http'
            URI("#{scheme}://#{@connection.address}:#{@connection.port}#{@request.path}")
        end
      end
    end
  end
end

