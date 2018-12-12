# frozen_string_literal: true

require "base64"
require "forwardable"
require "cuprite/browser/targets"
require "cuprite/browser/process"
require "cuprite/browser/client"
require "cuprite/browser/page"

module Capybara::Cuprite
  class Browser
    extend Forwardable

    attr_reader :headers

    def self.start(*args)
      new(*args)
    end

    attr_reader :process, :targets
    delegate %i(command subscribe) => :@client
    delegate %i(window_handle window_handles switch_to_window open_new_window
                close_window find_window_handle within_window page) => :@targets
    delegate %i(evaluate evaluate_async execute function) => :@evaluate
    delegate %i(click right_click double_click hover set click_coordinates
                drag drag_by select trigger scroll_to send_keys) => :@input

    def initialize(options = nil)
      @options = Hash(options)
      @logger = @options[:logger]
      start
    end

    def visit(url)
      page.visit(url)
    end

    def current_url
      evaluate("location.href", returnByValue: true)
    end

    def frame_url
      command "frame_url"
    end

    def status_code
      page.status_code
    end

    def body
      response = page.command("DOM.getDocument", depth: 0)
      response = page.command("DOM.getOuterHTML", nodeId: response["root"]["nodeId"])
      response["outerHTML"]
    end

    def source
      command "source"
    end

    def title
      evaluate("document.title", returnByValue: true)
    end

    def frame_title
      command "frame_title"
    end

    def parents(id)
      command "parents", id
    end

    def find(method, selector)
      find_all(method, selector)
    end

    def find_within(id, method, selector)
      find_all(method, selector, { "cupriteNodeId" => id })
    end

    def all_text(id)
      function("_cuprite.getNode(#{id}).allText")
    end

    def visible_text(id)
      begin
        function("_cuprite.getNode(#{id}).visibleText")
      rescue BrowserError => e
        # FIXME ObsoleteNode first arg is node, so it should be in node class
        if e.message == "No node with given id found"
          raise ObsoleteNode.new(self, e.response)
        end

        raise
      end
    end

    def delete_text(id)
      command "delete_text", id
    end

    def property(id, name)
      function("_cuprite.getNode(#{id}).property", name)
    end

    def attributes(id)
      function("_cuprite.getNode(#{id}).getAttributes")
    end

    def attribute(id, name)
      function("_cuprite.getNode(#{id}).getAttribute", name)
    end

    def value(id)
      function("_cuprite.getNode(#{id}).value")
    end

    def select_file(id, value)
      command "select_file", id, value
    end

    def tag_name(id)
      function("_cuprite.getNode(#{id}).tagName")
    end

    def visible?(id)
      function("_cuprite.getNode(#{id}).isVisible")
    end

    def disabled?(id)
      function("_cuprite.getNode(#{id}).isDisabled")
    end

    def within_frame(handle)
      if handle.is_a?(Capybara::Node::Base)
        command "push_frame", [handle.native.target_id, handle.native.node]
      else
        command "push_frame", handle
      end

      yield
    ensure
      command "pop_frame"
    end

    def switch_to_frame(handle)
      case handle
      when Capybara::Node::Base
        command "push_frame", [handle.native.target_id, handle.native.node]
      when :parent
        command "pop_frame"
      when :top
        command "pop_frame", true
      end
    end

    def render(path, _options = {})
      # check_render_options!(options)
      # options[:full] = !!options[:full]
      data = Base64.decode64(render_base64)
      File.open(path.to_s, "w") { |f| f.write(data) }
    end

    def render_base64(format = "png", _options = {})
      # check_render_options!(options)
      # options[:full] = !!options[:full]
      page.command("Page.captureScreenshot", format: format)["data"]
    end

    def set_zoom_factor(zoom_factor)
      command "set_zoom_factor", zoom_factor
    end

    def set_paper_size(size)
      command "set_paper_size", size
    end

    def resize(width, height)
      page.resize(width, height)
    end

    def path(target_id, node)
      function("_cuprite.getNode(#{id}).path")
    end

    def network_traffic(type = nil)
      page.network_traffic(type)
    end

    def clear_network_traffic
      page.clear_network_traffic
    end

    def set_proxy(ip, port, type, user, password)
      args = [ip, port, type]
      args << user if user
      args << password if password
      command("set_proxy", *args)
    end

    def headers=(headers)
      @headers = {}
      add_headers(headers)
    end

    def add_headers(headers, permanent: true)
      if headers["Referer"]
        page.referrer = headers["Referer"]
        headers.delete("Referer") unless permanent
      end

      @headers.merge!(headers)
      user_agent = @headers["User-Agent"]
      accept_language = @headers["Accept-Language"]

      set_overrides(user_agent: user_agent, accept_language: accept_language)
      page.command("Network.setExtraHTTPHeaders", headers: @headers)
    end

    def add_header(header, permanent: true)
      add_headers(header, permanent: permanent)
    end

    def set_overrides(user_agent: nil, accept_language: nil, platform: nil)
      options = Hash.new
      options[:userAgent] = user_agent if user_agent
      options[:acceptLanguage] = accept_language if accept_language
      options[:platform] if platform

      page.command("Network.setUserAgentOverride", **options) if !options.empty?
    end

    def response_headers
      page.response_headers
    end

    def cookies
      cookies = page.command("Network.getAllCookies")["cookies"]
      cookies.map { |c| [c["name"], Cookie.new(c)] }.to_h
    end

    def set_cookie(cookie)
      page.command("Network.setCookie", **cookie)
    end

    def remove_cookie(options)
      page.command("Network.deleteCookies", **options)
    end

    def clear_cookies
      page.command("Network.clearBrowserCookies")
    end

    def set_http_auth(user, password)
      command "set_http_auth", user, password
    end

    def page_settings=(settings)
      command "set_page_settings", settings
    end

    def url_whitelist=(whitelist)
      command "set_url_whitelist", *whitelist
    end

    def url_blacklist=(blacklist)
      command "set_url_blacklist", *blacklist
    end

    def clear_memory_cache
      page.command("Network.clearBrowserCache")
    end

    def go_back
      command "go_back"
    end

    def go_forward
      command "go_forward"
    end

    def refresh
      page.refresh
    end

    def accept_confirm
      command "set_confirm_process", true
    end

    def dismiss_confirm
      command "set_confirm_process", false
    end

    def accept_prompt(response)
      command "set_prompt_response", response || false
    end

    def dismiss_prompt
      command "set_prompt_response", nil
    end

    def modal_message
      command "modal_message"
    end

    def reset
      @headers = {}
      @targets.reset
    end

    def restart
      stop
      start
    end

    def stop
      @client.close
      @process.stop

      @client = @process = nil
      @targets = @evaluate = @input = nil
    end

    private

    def start
      @headers = {}
      @process = Process.start(@options)
      @client = Client.new(@process.ws_url, @logger)
      @targets = Targets.new(self, @logger)
      @evaluate = Evaluate.new(@targets)
      @input = Input.new(@targets, @evaluate)
    end

    def check_render_options!(options)
      return if !options[:full] || !options.key?(:selector)
      warn "Ignoring :selector in #render since :full => true was given at #{caller(1..1).first}"
      options.delete(:selector)
    end

    def find_all(method, selector, within = nil)
      begin
        args = [method, selector, within].compact
        function("_cuprite.find", *args).map do |n|
          within ? n["cupriteNodeId"] : [page.target_id, n["cupriteNodeId"]]
        end.compact
      rescue JavaScriptError => e
        if e.class_name == "InvalidSelector"
          raise InvalidSelector.new(e.response, method, selector)
        end
        raise
      end
    end
  end
end
