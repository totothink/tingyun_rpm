# encoding: utf-8
# This file is distributed under Ting Yun's license terms.


require 'ting_yun/agent'
require 'zlib'
require 'ting_yun/ting_yun_service/http'
require 'ting_yun/support/collector'
require 'ting_yun/support/serialize/encodes'
require 'ting_yun/support/timer_lib'
require 'ting_yun/support/exception'
require 'ting_yun/support/serialize/json_marshaller'
require 'ting_yun/ting_yun_service/upload_service'
require 'ting_yun/version'

module TingYun
  class TingYunService
    include Http
    include UploadService

    CONNECTION_ERRORS = [Timeout::Error, EOFError, SystemCallError, SocketError].freeze

    PROTOCOL_VERSION = 1


    attr_accessor :request_timeout,
                  :appSessionKey,
                  :data_version,
                  :metric_id_cache,
                  :applicationId,
                  :ssl_cert_store,
                  :shared_tcp_connection,
                  :quantile_cache,
                  :idSecret,
                  :config,
                  :attempts



    def initialize(license_key=nil)
      @license_key = license_key || TingYun::Agent.config[:'license_key']
      @request_timeout = TingYun::Agent.config[:timeout]
      @data_version =  ::TingYun::VERSION::DATA
      @marshaller =TingYun::Support::Serialize::JsonMarshaller.new
      @metric_id_cache = {}
      @quantile_cache = {}
      @hosts = TingYun::Agent.config[:collector_addresses].split(',')
    end

    def connect(settings={})
      if host = get_redirect_hostV3
        @collector = TingYun::Support.collector_from_host(host)
      end
      response = invoke_remote(:init, settings)
      @applicationId = response['appId']
      @appSessionKey = response['sessionKey'] unless response['sessionKey'].nil?
      @idSecret = response['idSecret']
      response
    end

    def get_redirect_host
      @collector=TingYun::Support.collector
      invoke_remote(:getRedirectHost)
    end

    def get_redirect_hostV3
      @attempts = 0
      max_attempts = @hosts.size
      begin
        @collector=TingYun::Support.collectorV3(@hosts[@attempts])
        @attempts += 1
        invoke_remote(:redirect)
      rescue => e
        if @attempts < max_attempts
          TingYun::Agent.logger.error(e)
          TingYun::Agent.logger.debug("Retrying request to #{@hosts[@attempts]}")
          TingYun::Support.reset
          retry
        else
          @attempts = 0
          TingYun::Support.reset
          retry
        end
      end
    end

    def force_restart
      @applicationId = nil
      @appSessionKey = nil
      @metric_id_cache = {}
      @quantile_cache = {}
      close_shared_connection
    end


    # send a message via post to the actual server. This attempts
    # to automatically compress the data via zlib if it is large
    # enough to be worth compressing, and handles any errors the
    # server may return

    # private

    def invoke_remote(method, payload={}, options ={})
      data = nil
      begin
        data = @marshaller.dump(payload, options)
      rescue StandardError, SystemStackError => e
        handle_serialization_error(method, e)
      end
      # serialize_finish_time = Time.now
      uri = remote_method_uri(method)
      full_uri = "http://#{@collector}#{uri}"

      if audit_mode?
        TingYun::Agent.logger.info("the prepare data: #{data} to url: #{full_uri}")
      else
        TingYun::Agent.logger.info("prepare to send data")
      end

      # data, encoding = compress_request_if_needed(data)
      response = send_requestV3(:data  => data,
                              :full_uri => full_uri,
                              :collector => @collector)

      if audit_mode?
        TingYun::Agent.logger.info("the return data: #{response.body}")
      else
        TingYun::Agent.logger.info("the send-process end")
      end
      @marshaller.load(decompress_response(response))
    end

    def audit_mode?
      TingYun::Agent.config[:'nbs.audit_mode']
    end

    def handle_serialization_error(method, e)
      msg = "Failed to serialize #{method} data using #{@marshaller.class.to_s}: #{e.inspect}"
      error = TingYun::Support::Exception::SerializationError.new(msg)
      error.set_backtrace(e.backtrace)
      raise error
    end

  end
end