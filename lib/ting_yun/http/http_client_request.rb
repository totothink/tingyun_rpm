require 'ting_yun/http/abstract_request'
module TingYun
  module Http
    class HttpClientRequest < AbstractRequest
      attr_reader :method, :header

      def initialize(proxy, *args, &block)
        @method, @uri, @query, @body, @header = args
        @proxy = proxy
        @block = block
      end

      def type
        @uri.scheme
      end

      def from
        "HttpClient"
      end

      def host
        @uri.host || @proxy.host
      end
      def port
        @uri.port || @uri.port
      end

      def [](key)
        @header[key]
      end

      def []=(key, value)
        @header[key] = value
      end

      def uri
        return @uri if @uri.scheme && @uri.host && @uri.port
        URI("#{@proxy.scheme.downcase}://#{@proxy.host}:#{@proxy.port}#{@uri}")
      end

      def path
        @uri
      end

      def args
        return @method, @uri, @query, @body, @header
      end
    end
  end
end