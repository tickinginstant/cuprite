# frozen_string_literal: true

require "forwardable"

module Capybara::Cuprite
  class Evaluate
    EXECUTE = {
      returnByValue: true,
      functionDeclaration: %Q(function() {
        _cuprite._prepareArgs(arguments);
        %s
      }).strip
    }.freeze
    EVALUATE = {
      returnByValue: true,
      functionDeclaration: %Q(function() {
        return _cuprite.evaluate(function() { return %s; }, arguments);
      }).strip
    }.freeze
    EVALUATE_ASYNC = {
      awaitPromise: true,
      returnByValue: true,
      functionDeclaration: %Q(function() {
        return _cuprite.evaluate_async(function() { %s }, arguments);
      }).strip
    }.freeze

    extend Forwardable

    delegate page: :@targets

    def initialize(targets)
      @targets = targets
    end

    def evaluate(expr, *args, **options)
      options = EVALUATE.merge(options)
      response = call(expr, options, *args)
      options[:returnByValue] ? response["value"] : handle(response)
    end

    def evaluate_async(expr, _wait_time, *args, **options)
      options = EVALUATE_ASYNC.merge(options)
      response = call(expr, options, *args)
      options[:returnByValue] ? response["value"] : handle(response)
    end

    def execute(expr, *args, **options)
      options = EXECUTE.merge(options)
      call(expr, options, *args)
      true
    end

    def function(name, *args, method: :evaluate, **options)
      options = options.merge(returnByValue: true) if options.empty?
      fun_args = (0..args.size - 1).map { |x| "arguments[#{x}]" }.join(', ')
      send(method, "#{name}(#{fun_args})", *args, **options)
    end

    private

    def call(expr, options = nil, *args)
      options ||= {}
      args = prepare(args)
      function = options[:functionDeclaration] % expr

      unless options[:objectId]
        options = options.merge(executionContextId: page.execution_context_id)
      end

      options = options.merge(arguments: args, functionDeclaration: function)
      response = page.command("Runtime.callFunctionOn", **options)["result"]
      raise JavaScriptError.new(response) if response["subtype"] == "error"
      response
    end

    def prepare(args)
      args.map do |arg|
        if arg.is_a?(Node)
          { value: { cupriteNodeId: arg.native.id } }
        elsif arg.is_a?(Hash) && arg["cupriteNodeId"]
          { value: arg.slice("cupriteNodeId") }
        else
          { value: arg }
        end
      end
    end

    def handle(response, cleanup = true)
      case response["type"]
      when "boolean", "number", "string"
        response["value"]
      when "undefined"
        nil
      when "function"
        response["description"]
      when "object"
        case response["subtype"]
        when "node"
          response
        when "array"
          response
        when "date"
          response["description"]
        when "null"
          nil
        else
          response
        end
      end
    end
  end
end
