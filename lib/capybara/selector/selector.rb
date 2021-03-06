# frozen_string_literal: true
require 'capybara/selector/filter_set'
require 'xpath'

#Patch XPath to allow a nil condition in where
module XPath
  class Renderer
    def where(on, condition)
      condition = condition.to_s
      if !condition.empty?
        "#{on}[#{condition}]"
      else
        "#{on}"
      end
    end
  end
end

module Capybara
  class Selector

    attr_reader :name, :format, :expression_filters

    class << self
      def all
        @selectors ||= {}
      end

      def add(name, &block)
        all[name.to_sym] = Capybara::Selector.new(name.to_sym, &block)
      end

      def update(name, &block)
        all[name.to_sym].instance_eval(&block)
      end

      def remove(name)
        all.delete(name.to_sym)
      end
    end

    def initialize(name, &block)
      @name = name
      @filter_set = FilterSet.add(name){}
      @match = nil
      @label = nil
      @failure_message = nil
      @description = nil
      @format = nil
      @expression = nil
      @expression_filters = []
      instance_eval(&block)
    end

    def custom_filters
      @filter_set.filters
    end

    ##
    #
    # Define a selector by an xpath expression
    #
    # @overload xpath(*expression_filters, &block)
    #   @param [Array<Symbol>] expression_filters ([])  Names of filters that can be implemented via this expression
    #   @yield [locator, options]                       The block to use to generate the XPath expression
    #   @yieldparam [String] locator                    The locator string passed to the query
    #   @yieldparam [Hash] options                      The options hash passed to the query
    #   @yieldreturn [#to_xpath, #to_s]                 An object that can produce an xpath expression
    #
    # @overload xpath()
    # @return [#call]                             The block that will be called to generate the XPath expression
    #
    def xpath(*expression_filters, &block)
      @format, @expression_filters, @expression = :xpath, expression_filters.flatten, block if block
      format == :xpath ? @expression : nil
    end

    ##
    #
    # Define a selector by a CSS selector
    #
    # @overload css(*expression_filters, &block)
    #   @param [Array<Symbol>] expression_filters ([])  Names of filters that can be implemented via this CSS selector
    #   @yield [locator, options]                   The block to use to generate the CSS selector
    #   @yieldparam [String] locator               The locator string passed to the query
    #   @yieldparam [Hash] options                 The options hash passed to the query
    #   @yieldreturn [#to_s]                        An object that can produce a CSS selector
    #
    # @overload css()
    # @return [#call]                             The block that will be called to generate the CSS selector
    #
    def css(*expression_filters, &block)
      @format, @expression_filters, @expression = :css, expression_filters.flatten, block if block
      format == :css ? @expression : nil
    end

    ##
    #
    # Automatic selector detection
    #
    # @yield [locator]                   This block takes the passed in locator string and returns whether or not it matches the selector
    # @yieldparam [String], locator      The locator string used to determin if it matches the selector
    # @yieldreturn [Boolean]             Whether this selector matches the locator string
    # @return [#call]                    The block that will be used to detect selector match
    #
    def match(&block)
      @match = block if block
      @match
    end

    ##
    #
    # Set/get a descriptive label for the selector
    #
    # @overload label(label)
    #   @param [String] label            A descriptive label for this selector - used in error messages
    # @overload label()
    # @return [String]                 The currently set label
    #
    def label(label=nil)
      @label = label if label
      @label
    end

    ##
    #
    # Description of the selector
    #
    # @param [Hash] options            The options of the query used to generate the description
    # @return [String]                 Description of the selector when used with the options passed
    #
    def description(options={})
      @filter_set.description(options)
    end

    def call(locator, options={})
      if format
        # @expression.call(locator, options.select {|k,v| @expression_filters.include?(k)})
        @expression.call(locator, options)
      else
        warn "Selector has no format"
      end
    end

    ##
    #
    #  Should this selector be used for the passed in locator
    #
    #  This is used by the automatic selector selection mechanism when no selector type is passed to a selector query
    #
    # @param [String] locator     The locator passed to the query
    # @return [Boolean]           Whether or not to use this selector
    #
    def match?(locator)
      @match and @match.call(locator)
    end

    ##
    #
    # Define a non-expression filter for use with this selector
    #
    # @overload filter(name, *types, options={}, &block)
    #   @param [Symbol] name            The filter name
    #   @param [Array<Symbol>] types    The types of the filter - currently valid types are [:boolean]
    #   @param [Hash] options ({})      Options of the filter
    #   @option options [Array<>] :valid_values Valid values for this filter
    #   @option options :default        The default value of the filter (if any)
    #   @option options :skip_if        Value of the filter that will cause it to be skipped
    #
    def filter(name, *types_and_options, &block)
      options = types_and_options.last.is_a?(Hash) ? types_and_options.pop.dup : {}
      types_and_options.each { |k| options[k] = true}
      custom_filters[name] = Filter.new(name, block, options)
    end

    def filter_set(name, filters_to_use = nil)
      f_set = FilterSet.all[name]
      f_set.filters.each do | name, filter |
        custom_filters[name] = filter if filters_to_use.nil? || filters_to_use.include?(name)
      end
      f_set.descriptions.each { |desc| @filter_set.describe &desc }
    end

    def describe &block
      @filter_set.describe &block
    end

    private

    def locate_field(xpath, locator, options={})
      locate_xpath = xpath #need to save original xpath for the label wrap
      if locator
        locator = locator.to_s
        attr_matchers =  XPath.attr(:id).equals(locator) |
                         XPath.attr(:name).equals(locator) |
                         XPath.attr(:placeholder).equals(locator) |
                         XPath.attr(:id).equals(XPath.anywhere(:label)[XPath.string.n.is(locator)].attr(:for))
        attr_matchers |= XPath.attr(:'aria-label').is(locator) if Capybara.enable_aria_label

        locate_xpath = locate_xpath[attr_matchers]
        locate_xpath += XPath.descendant(:label)[XPath.string.n.is(locator)].descendant(xpath)
      end

      locate_xpath = [:id, :name, :placeholder, :class].inject(locate_xpath) { |memo, ef| memo[find_by_attr(ef, options[ef])] }
      locate_xpath
    end

    def find_by_attr(attribute, value)
      finder_name = "find_by_#{attribute.to_s}_attr"
      if respond_to?(finder_name, true)
        send(finder_name, value)
      else
        value ? XPath.attr(attribute).equals(value) : nil
      end
    end

    def find_by_class_attr(classes)
      if classes
        Array(classes).map do |klass|
          "contains(concat(' ',normalize-space(@class),' '),' #{klass} ')"
        end.join(" and ").to_sym
      else
        nil
      end
    end
  end
end
