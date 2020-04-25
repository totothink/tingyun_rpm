TingYun::Support::LibraryDetection.defer do
  named :bunny

  depends_on do
    defined?(::Bunny::VERSION)
  end
  depends_on do
    !::TingYun::Agent.config[:disable_rabbitmq]
  end



  executes do
    TingYun::Agent.logger.info 'Installing bunny(for rabbitmq) Instrumentation'
    require 'ting_yun/support/helper'
    require 'ting_yun/instrumentation/support/external_helper'
  end

  executes do
    ::Bunny::Exchange.class_eval do

      if public_method_defined? :publish
        include TingYun::Instrumentation::Support::ExternalHelper
        def publish_with_tingyun(payload, opts = {})
          begin
            state = TingYun::Agent::TransactionState.tl_get
            return publish_without_tingyun(payload, opts) unless state.execution_traced?
            queue_name = opts[:routing_key]
            metric_name = "Message RabbitMQ/#{@channel.connection.host}:#{@channel.connection.port}/"
            if name.empty?
              if queue_name.start_with?("amq.")
                metric_name << "Queue/Temp/Produce"
              elsif queue_name.include?(".")
                metric_name << "Topic/#{queue_name}/Produce"
              else
                metric_name << "Queue/#{queue_name}/Produce"
              end
            else
              metric_name << "Exchange/#{name}/Produce"
            end
            summary_metrics = TingYun::Instrumentation::Support::ExternalHelper.metrics_for_message('RabbitMQ', "#{@channel.connection.host}:#{@channel.connection.port}", 'Produce')
            TingYun::Agent::MethodTracerHelpers.trace_execution_scoped(summary_metrics.unshift(metric_name), {}, nil, "Bunny/Exchange") do
              opts[:headers] = {} unless opts[:headers]
              opts[:headers]["X-Tingyun"] = create_tingyun_id  if TingYun::Agent.config[:'nbs.transaction_tracer.enabled']
              state.add_current_node_paramsV3(:vendor => "RabbitMQ")
              state.add_current_node_paramsV3(:instance => "#{@channel.connection.host}:#{@channel.connection.port}")
              state.add_current_node_paramsV3(:operation => "#{queue_name} #{self.name}",:key=> self.name)
              state.add_current_node_params(:type => 'MQP',:method=>"publish")
              # TingYun::Agent.record_metric("#{metric_name}/Byte",payload.bytesize) if payload
              publish_without_tingyun(payload, opts)
            end
          rescue => e
            TingYun::Agent.logger.error("Failed to Bunny publish_with_tingyun : ", e)
            publish_without_tingyun(payload, opts)
          end
        end




        alias_method :publish_without_tingyun, :publish
        alias_method :publish, :publish_with_tingyun
      end

    end

    ::Bunny::Consumer.class_eval do

      if public_method_defined?(:call)

        def call_with_tingyun(*args)
          return call_without_tingyun(*args) unless TingYun::Agent.config[:'mq.enabled']
          begin

            headers = args[1][:headers].clone rescue {}


            tingyun_id_secret = headers["X-Tingyun"]

            state = TingYun::Agent::TransactionState.tl_get

            if queue_name.start_with?("amq.")
              metric_name = "#{@channel.connection.host}:#{@channel.connection.port}/Queue/Temp/Consume"
              transaction_name = "RabbitMQ/Queue/FTemp"
            elsif queue_name.include?(".")
              metric_name = "#{@channel.connection.host}:#{@channel.connection.port}/Topic/#{queue_name}/Consume"
              transaction_name = "RabbitMQ/Topic/#{queue_name}"
            else
              metric_name = "#{@channel.connection.host}:#{@channel.connection.port}/Queue/#{queue_name}/Consume"
              transaction_name = "RabbitMQ/Queue/#{queue_name}"
            end

            state.save_referring_transaction_info(tingyun_id_secret.split(';')) if cross_app_enabled?(tingyun_id_secret)

            summary_metrics = TingYun::Instrumentation::Support::ExternalHelper.metrics_for_message('RabbitMQ', "#{@channel.connection.host}:#{@channel.connection.port}", 'Consume')
            TingYun::Agent::Transaction.wrap(state, "Message RabbitMQ/#{metric_name}" , :message, {:mq=> true}, summary_metrics)  do
              TingYun::Agent::Transaction.set_frozen_transaction_name!("#{state.action_type}/#{transaction_name}")
              # TingYun::Agent.record_metric("Message RabbitMQ/#{metric_name}/Byte",args[2].bytesize) if args[2]
              # TingYun::Agent.record_metric("Message RabbitMQ/#{metric_name}Wait", TingYun::Helper.time_to_millis(Time.now)-state.externel_time.to_i) rescue 0
              state.add_custom_params("message.routingkey",queue_name)
              state.add_current_node_params(:type => 'MQC',:method=>"call",:klass=> "Bunny/Consumer")
              state.current_transaction.attributes.add_agent_attribute(:tx_id, state.client_transaction_id)
              headers.delete("X-Tingyun")
              state.merge_request_parameters(headers)
              call_without_tingyun(*args)
              tx_data =  build_payload(state)
              state.current_transaction.attributes.add_agent_attribute(:entryTrace,tx_data) if TingYun::Agent.config[:'nbs.transaction_tracer.enabled']
              state.add_current_node_paramsV3(:vendor => "RabbitMQ",:key => queue_name)
              state.add_current_node_paramsV3(:txData => TingYun::Support::Serialize::JSONWrapper.dump(tx_data))
              state.add_current_node_paramsV3(:instance => "#{@channel.connection.host}:#{@channel.connection.port}")
              state.add_current_node_paramsV3(:operation => "#{queue_name}",:bytes =>args[2].bytesize,:async_wait=>TingYun::Helper.time_to_millis(Time.now)-state.externel_time.to_i)
            end
          rescue => e
            TingYun::Agent.logger.error("Failed to Bunny call_with_tingyun : ", e)
            call_without_tingyun(*args)
          end

        end
        alias_method :call_without_tingyun, :call
        alias_method :call, :call_with_tingyun

      end

      def cross_app_enabled?(tingyun_id_secret)
        tingyun_id_secret && ::TingYun::Agent.config[:idSecret] && TingYun::Agent.config[:'nbs.transaction_tracer.enabled']
      end

      def build_payload(state)
        timings = state.timings

        payload = {
            :id => TingYun::Agent.config[:idSecret],
            :tname => state.transaction_name,
            :tid => state.current_transaction.guid,
            :rid => state.trace_id,
            :duration => timings.app_time_in_millis
        }

        payload
      end
    end

    ::Bunny::Channel.class_eval do
      if public_method_defined?(:basic_get)
        def basic_get_with_tingyun(*args)
          return basic_get_without_tingyun(*args) unless TingYun::Agent.config[:'mq.enabled']
          begin
            state = TingYun::Agent::TransactionState.tl_get
            metric_name = "#{@connection.host}:#{@connection.port}/Queue/#{args[0]}/Consume"
            summary_metrics = TingYun::Instrumentation::Support::ExternalHelper.metrics_for_message('RabbitMQ', "#{connection.host}:#{connection.port}", 'Consume')
            TingYun::Agent::MethodTracerHelpers.trace_execution_scoped(summary_metrics, {}, nil, "Bunny/Channel") do
              basic_get_without_tingyun(*args)
              state.add_current_node_paramsV3(:vendor => "RabbitMQ")
              state.add_current_node_paramsV3(:instance => "#{@connection.host}:#{@connection.port}")
              state.add_current_node_paramsV3(:operation => "#{args[0]}")
              state.add_current_node_params(:type => 'MQC',:method=>"basic_get")
            end
          rescue =>e
            TingYun::Agent.logger.error("Failed to Bunny basic_get_with_tingyun : ", e)
            basic_get_without_tingyun(*args)
          # ensure
          #   TingYun::Agent::Transaction.stop(state, Time.now.to_f, summary_metrics)
          end
        end

        alias_method :basic_get_without_tingyun, :basic_get
        alias_method :basic_get, :basic_get_with_tingyun
      end
    end
  end

end