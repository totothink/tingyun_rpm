# encoding: utf-8

module TingYun
  module Instrumentation
    module Support
      module EventFormatter
        def self.format(command_name, database_name, command,host="localhost",port="27017", nosql="")
          result = {
              :operation => command_name,
              :database => database_name,
              :collection => command.values.first,
              :term => command.values.last,
              :product => "Mongo",
              :type=>"Mongo",
              :host => host,
              :port => port,
              :nosql => nosql
          }
          result
        end
      end
    end
  end
end
