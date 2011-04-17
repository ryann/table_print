# future work:
#
#   handle multi-level includes like 'tp User.all, :include => "blogs.title"' and ActiveRecord associations
#   allow other output venues besides 'puts'
#   allow fine-grained formatting
#   on-the-fly column definitions (pass a proc as an include, eg 'tp User.all, :include => {:column_name => "Zodiac", :display_method => lambda {|u| find_zodiac_sign(u.birthday)}}')
#   allow user to pass ActiveRelation instead of a data array? That could open up so many options!
#   a :short_booleans method could save a little space (replace true/false with T/F or 1/0)
#
# bugs
#
#   handle multibyte (see https://skitch.com/arches/r3cbg/multibyte-bug)

class TablePrint

  # TODO: make options for things like MAX_FIELD_LENGTH
  # TODO: make options for things like separator
  # TODO: make options for things like column order
  def initialize(options = {})
  end

  # TODO: show documentation if invoked with no arguments
  # TODO: use *args instead of options
  def tp(data, options = {})
    data = wrap(data).compact

    # nothing to see here
    if data.empty?
      return "No data."
    end

    separator = "  | "

    display_methods = get_display_methods(data.first, options)
    unless display_methods.length > 0
      return data.inspect.to_s
    end

    # we're going to load all the data into memory so we can calculate field lengths.
    # TODO: there has to be a better way than loading everything into memory
    # TODO: stop checking field length once we hit the max
    # TODO: don't check field length on fixed-width columns

    # make columns for all the display methods
    columns = display_methods.collect { |m| Column.new(data, m, options[m] || options[m.to_sym]) }

    output = [] # a list of rows.  we'll join this with newlines when we're done

    # column headers
    row = []
    columns.each do |column|
      row << column.formatted_header
    end
    output << row.join(separator)

    # a row of hyphens to separate the headers from the data
    output << ("-" * row.join(separator).length)

    # the data!
    data.each do |data_obj|
      row = []
      columns.each do |column|
        row << column.formatted_field_value(data_obj)
      end
      output << row.join(separator)
    end

    output.join("\n")
  end

  private

  def get_display_methods(data_obj, options)
    # determine what methods we're going to use

    # using options:
    # TODO: maybe rename these a little? cascade/include are somewhat mixed with respect to rails lexicon
    #   :except - use the default set of methods but NOT the ones passed here
    #   :include - use the default set of methods AND the ones passed here
    #   :only - discard the default set of methods in favor of this list
    #   :cascade -
    #
    # eg
    #
    # tp User.limit(30) # default to using AR columns
    # tp User.limit(30) :except => :display_name
    # tp User.limit(30) :except => [:display_name, :created_at]
    # tp User.limit(30) :except => [:display_name, :timestamps] # a rails convention - but this could just be a type-based filter instead of method-based?
    # tp User.limit(30) :include => :status     # not an AR column
    # tp User.limit(30) :except => :display_name
    # tp User.limit(30) :except => :display_name
    # tp User.limit(30) :except => :display_name
    # tp User.limit(30) :except => :display_name
    #
    # tp User.include(:blogs).limit(30) :cascade => :blog
    # tp User.limit(30) :include => "blog.title"  # use dot notation to traverse children
    # TODO: how to handle multiple children? eg, a user has fifteen blogs
    #
    # tp [myClassInstance1, ...]  # default to using non-base methods
    # tp [myClassInstance1, ...] :except => :blah
    # tp [myClassInstance1, ...] :except => [:blah, :blow]
    # tp [myClassInstance1, ...] :include => :blah
    # tp [myClassInstance1, ...] :include => [:blah, :blow]
    # tp [myClassInstance1, ...] :include => :blah, :except => :blow
    # tp [myClassInstance1, ...] :only => [:one, :two, :three]

    if options.has_key? :only or options.has_key? "only"
      display_methods = clean_display_methods(data_obj, wrap(options[:only]))
      return display_methods if display_methods.length > 0
    end

    # make all the options into arrays
    methods_to_include = clean_display_methods(data_obj, wrap(options[:include]))
    methods_to_except = clean_display_methods(data_obj, wrap(options[:except]))

    # add/remove the includes/excludes from the defaults
    display_methods = get_default_display_methods(data_obj)
    display_methods.concat(methods_to_include).uniq!
    display_methods - methods_to_except
  end

  def get_default_display_methods(data_obj)
    # ActiveRecord
    return data_obj.class.columns.collect { |c| c.name } if defined?(ActiveRecord) and data_obj.is_a? ActiveRecord::Base

    # base types
    # TODO: fill out this list. any way to get this programatically? do we actually want to filter out all base ruby types? important question for custom classes inheriting from base types
    return [] if [Float, Fixnum, String, Numeric, Array, Hash].include? data_obj.class

    # custom class
    methods = data_obj.class.instance_methods - Object.instance_methods # TODO: need to filter based on data_obj.class, if it's a Hash or Array we're missing a lot here
    methods.delete_if { |m| m[-1].chr == "=" } # don't use assignment methods
    methods.map! { |m| m.to_s } # make any symbols into strings
    methods
  end

  def clean_display_methods(data_obj, display_methods)
    # TODO: this should probably be inside Column
    clean_methods = []
    display_methods.each do |m|
      next if m.nil?
      next if m == ""
      next unless data_obj.respond_to? m
      clean_methods << m.to_s
    end
    clean_methods.uniq
  end

  # borrowed from rails
  def wrap(object)
    if object.nil?
      []
    elsif object.respond_to?(:to_ary)
      object.to_ary
    else
      [object]
    end
  end

  class Column
    attr_accessor :name, :display_method, :options, :data, :field_length, :max_field_length

    def initialize(data, display_method, options = {})
      self.options = options || {}    # could have been passed an explicit nil
      self.display_method = display_method
      self.name = self.options[:name] || display_method.gsub("_", " ")
      self.max_field_length = self.options[:max_field_length] || 30
      self.max_field_length = [self.max_field_length, 1].max  # numbers less than one are meaningless

      # initialization
      self.initialize_field_length(data)
    end

    def formatted_header
      "%-#{self.field_length}s" % truncate(self.name.upcase)
    end

    def formatted_field_value(data_obj)
      "%-#{self.field_length}s" % truncate(data_obj.send(self.display_method).to_s)
    end

    def initialize_field_length(data)
      # skip all this nonsense if we've been explicitly told what to do
      if self.options[:field_length] and self.options[:field_length] > 0
        length = self.options[:field_length]
      else
        length = self.name.length # it has to at least be long enough for the column header!

        start = Time.now
        data.each do |data_obj|
          next if data_obj.nil?

          # fixed-width fields don't require the full loop
          case data_obj.send(self.display_method)
            when Time
              length = data_obj.send(self.display_method).to_s.length
              break
            when TrueClass, FalseClass
              length = [5, length].max
              break
          end

          length = [length, data_obj.send(self.display_method).to_s.length].max
          break if length >= self.max_field_length # we're never going to longer than the global max, so why keep going
          break if (Time.now - start) > 2 # assume if we loop for more than 2s that we've made it through a representative sample, and bail
        end
      end

      self.field_length = [length, self.max_field_length].min   # never bigger than the max
    end

    private
    
    def truncate(field_value)
      copy = String.new(field_value)
      if copy.length > self.max_field_length
        copy = copy[0..self.max_field_length-1]
        copy[-3..-1] = "..." unless self.max_field_length <= 3 # don't use ellipses when the string is tiny
      end
      copy
    end
  end
end

module Kernel
  def tp(data, options = {})
    start = Time.now
    table_print = TablePrint.new
    puts table_print.tp(data, options)
    Time.now - start
  end

  module_function :tp
end










