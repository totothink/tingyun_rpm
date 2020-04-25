# encoding: utf-8

require 'digest'

module TingYun
  module Instrumentation
    module Support
      module ExternalHelper
        def create_tingyun_idV2(protocol)
          state = TingYun::Agent::TransactionState.tl_get
          externel_guid = tingyun_externel_guid
          state.extenel_req_id = externel_guid
          cross_app_id  = TingYun::Agent.config[:idSecret] or
              raise TingYun::Agent::CrossAppTracing::Error, "no idSecret configured"
          state.add_current_node_params(:tx_id=>state.request_guid, :externalId=>state.extenel_req_id)
          "#{cross_app_id};c=1;x=#{state.request_guid};e=#{externel_guid};s=#{TingYun::Helper.time_to_millis(Time.now)};p=#{protocol}"
        end

        def create_tingyun_id(protocol=nil,vendor=nil,request=nil)
          state = TingYun::Agent::TransactionState.tl_get
          if state.transaction_name_md5.nil?
            tmd5 = Digest::MD5.hexdigest(state.current_transaction.best_name)
          else
            tmd5 = state.transaction_name_md5
          end
          externel_guid = tingyun_externel_guid
          state.add_current_node_paramsV3(:externalId => externel_guid)
          unless request.nil?
            state.add_current_node_paramsV3(:protocol=> request.type)
            state.add_current_node_paramsV3(:instance=> "#{request.host}:#{request.port}")
            state.add_current_node_paramsV3(:operation=> request.path)
            state.add_current_node_paramsV3(:vendor => request.from)
          else
            state.add_current_node_paramsV3(:protocol => protocol) unless protocol.nil?
            state.add_current_node_paramsV3(:vendor => vendor) unless vendor.nil?
          end
          state.add_current_node_params(:type=> "External")
          "c=S|#{state.client_tingyun_id_secret};x=#{state.request_guid};e=#{externel_guid};n=#{tmd5}"
        end

        # generate a random 64 bit uuid
        def tingyun_externel_guid
          guid = ''
          16.times do
            guid << (0..15).map{|i| i.to_s(16)}[rand(16)]
          end
          guid
        end

        def self.metrics_for_message(product, ip_host, operation)
          if TingYun::Agent::Transaction.recording_web_transaction?
            metrics =["AllWeb", "All"]
          else
            metrics =["AllBackground", "All"]
          end

          metrics = metrics.map { |suffix| "Message #{product}/NULL/#{suffix}" }
          metrics.unshift "Message #{product}/#{ip_host}/#{operation}"
        end
      end
    end
  end
end


