# encoding: utf-8
require 'ting_yun/support/helper'
require 'ting_yun/support/coerce'
require 'ting_yun/agent/database'


module TingYun
  module Agent
    class Transaction
      class TraceNode

        attr_reader :entry_timestamp, :parent_node, :called_nodes
        attr_accessor :metric_name, :exit_timestamp, :uri, :count, :klass, :method, :name

        attr_accessor :tracerId, :parentTracerId, :type,:params_data,:datas,:backtrace,:exception



        UNKNOWN_NODE_NAME = '<unknown>'.freeze


        def initialize(timestamp, metric_name,tracerId,option={})
          @type = option[:type] || 'Java'
          @entry_timestamp = timestamp
          @metric_name     = metric_name
          @called_nodes    = nil
          @count           = 1
          if metric_name == "ROOT"
            @parentTracerId = -1
            @tracerId = 0
          else
            @tracerId = tracerId
          end
          @exception = []
          @params_data = {}
          @backtrace = []
        end

        def add_called_node(s)
          @called_nodes ||= []
          @called_nodes << s
          s.parent_node = self
        end

        def end_trace(timestamp)
          @parentTracerId = @parent_node.tracerId  unless @parent_node.nil?
          @exit_timestamp = timestamp
        end

        # return the total duration of this node
        def duration
          TingYun::Helper.time_to_millis(@exit_timestamp - @entry_timestamp)
        end


        def pre_metric_name(metric_name)
          @name ||= if metric_name.start_with?('Database ')
                      "#{metric_name.split('/')[0]}/#{metric_name.split('/')[-1]}"
                    else
                      metric_name
                    end
        end

        def to_array
          [TingYun::Helper.time_to_millis(entry_timestamp),
           TingYun::Helper.time_to_millis(exit_timestamp),
           TingYun::Support::Coerce.string(metric_name),
           TingYun::Support::Coerce.string(uri)||'',
           TingYun::Support::Coerce.int(count),
           TingYun::Support::Coerce.string(klass)||TingYun::Support::Coerce.string(pre_metric_name(metric_name)),
           TingYun::Support::Coerce.string(method)||'',
           params] +
              [(@called_nodes ? @called_nodes.map{|s| s.to_array} : [])]
        end

        def to_hash
          hash =  {
              "parentTracerId" => @parentTracerId,
              "start" => TingYun::Helper.time_to_millis(entry_timestamp),
              "end" =>  TingYun::Helper.time_to_millis(exit_timestamp),
              "type"=>  params[:type] || @type
          }
          hash["tracerId"]= @tracerId if @tracerId!=0
          method =  params[:method] || TingYun::Support::Coerce.string(method)
          hash["method"] = method unless method.nil?
          hash["metric"] = TingYun::Support::Coerce.string(metric_name) unless (metric_name.nil? or metric_name=="ROOT")
          clazz =   params[:klass] || TingYun::Support::Coerce.string(klass)
          hash["clazz"] = clazz unless clazz.nil?
          hash["params"] = params_data unless params_data.empty?
          hash["backtrace"] = backtrace unless backtrace.empty?
          hash["exception"] = exception unless exception.empty?
          [hash].concat([(@called_nodes ? @called_nodes.map{|s| s.to_hash} : nil)].compact)
        end

        def custom_params
          {}
        end

        def request_params
          {}
        end

        def []=(key, value)
          # only create a parameters field if a parameter is set; this will save
          # bandwidth etc as most nodes have no parameters
          params[key] = value
        end

        def [](key)
          params[key]
        end

        def params
          @params ||= {}
        end

        def params=(p)
          @params = p
        end

        def merge(hash)
          params.merge! hash
        end

        def each_call(&blk)
          blk.call self

          if @called_nodes
            @called_nodes.each do |node|
              node.each_call(&blk)
            end
          end
        end

        def explain_sql
          return params[:explainPlan] if params.key?(:explainPlan)

          statement = params[:sql]
          return nil unless statement.respond_to?(:config) &&
              statement.respond_to?(:explainer)

          TingYun::Agent::Database.explain_sql(statement)
        end

        def add_error(error)
          if error.respond_to?(:tingyun_external)
            exception << {"msg" => error.message,
                          "name" => "External #{error.tingyun_code}",
                          "stack"=> error.backtrace,
                          "error"=> false
            }
          else
            if ::TingYun::Agent.config[:'nbs.exception.stack_enabled']
              exception << {"msg" => error.message,
                            "name" => error.class.name ,
                            "stack"=> error.backtrace.reject! { |t| t.include?('tingyun_rpm') },
                            "error"=> false
              }
            else
              exception << {"msg" => error.message,
                            "name" => error.class.name,
                            "stack"=> error.backtrace,
                            "error"=> false
              }
            end
          end
        end

        protected
        def parent_node=(s)
          @parent_node = s
        end
      end
    end
  end
end
