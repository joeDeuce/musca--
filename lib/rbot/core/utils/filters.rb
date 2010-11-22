#-- vim:sw=2:et
#++
#
# :title: Stream filters
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# This file collects methods to handle 'stream filters', a generic mechanism
# to transform text+attributes into other text+attributes

module ::Irc
  class Bot

    # The DataStream class. A DataStream is just a Hash. The :text key has
    # a special meaning because it's the value that will be used when
    # converting to String
    class DataStream < Hash

      # call-seq: new(text, hash)
      #
      # Create a new DataStream with text _text_ and attributes held by _hash_.
      # Either parameter can be missing; if _text_ is missing, the text can be
      # be defined in the _hash_ with a :text key.
      #
      def initialize(*args)
        self.replace(args.pop) if Hash === args.last
        self[:text] = args.first if args.length > 0
      end

      # Returns the :text key
      def to_s
        return self[:text]
      end
    end

    # The DataFilter class. A DataFilter is a wrapper around a block
    # that can be run on a DataStream to process it. The block is supposed to
    # return another DataStream object
    class DataFilter
      def initialize(&block)
        raise "No block provided" unless block_given?
        @block = block
      end

      def call(stream)
        @block.call(stream)
      end
      alias :run :call
      alias :filter :call
    end

    # call-seq:
    #   filter(filter1, filter2, ..., filterN, stream) -> stream
    #   filter(filter1, filter2, ..., filterN, text, hash) -> stream
    #   filter(filter1, filter2, ..., filterN, hash) -> stream
    #
    # This method processes the DataStream _stream_ with the filters <i>filter1</i>,
    # <i>filter2</i>, ..., _filterN_, in sequence (the output of each filter is used
    # as input for the next one.
    # _stream_ can be provided either as a DataStream or as a String and a Hash
    # (see DataStream.new).
    #
    def filter(*args)
      @filters ||= {}
      if Hash === args.last
        # the stream is a Hash, check if the previous element is not a Symbol
        if Symbol === args[-2]
          ds = DataStream.new(args.pop)
        else
          ds = DataStream.new(*args.slice!(-2, 2))
        end
      else
        # the stream is just whatever else
        ds = DataStream.new(args.pop)
      end
      names = args.dup
      return ds if names.empty?
      # check if filters exist
      missing = names - @filters.keys
      raise "Missing filters: #{missing.join(', ')}" unless missing.empty?
      fs = @filters.values_at(*names)
      fs.inject(ds) { |mid, f| mid = f.call(mid) }
    end

    # This method returns the global filter name for filter _name_
    # in group _group_
    def global_filter_name(name, group=nil)
      (group ? "#{group}.#{name}" : name.to_s).intern
    end

    # This method checks if the bot has a filter named _name_ (in group
    # _group_)
    def has_filter?(name, group=nil)
      @filters.key?(global_filter_name(name, group))
    end

    # This method checks if the bot has a filter group named _name_
    def has_filter_group?(name)
      @filter_group.key?(name)
    end

    # This method is used to register a new filter
    def register_filter(name, group=nil, &block)
      raise "No block provided" unless block_given?
      @filters ||= {}
      tlkey = global_filter_name(name, group)
      key = name.to_sym
      if has_filter?(tlkey)
        debug "Overwriting filter #{tlkey}"
      end
      @filters[tlkey] = DataFilter.new(&block)
      if group
        gkey = group.to_sym
        @filter_group ||= {}
        @filter_group[gkey] ||= {}
        if @filter_group[gkey].key?(key)
          debug "Overwriting filter #{key} in group #{gkey}"
        end
        @filter_group[gkey][key] = @filters[tlkey]
      end
    end

    # This method is used to retrieve the filter names (in a given group)
    def filter_names(group=nil)
      if group
        gkey = group.to_sym
        return [] unless defined? @filter_group and @filter_group.key?(gkey)
        return @filter_group[gkey].keys
      else
        return [] unless defined? @filters
        return @filters.keys
      end
    end

    # This method is used to retrieve the filter group names
    def filter_groups
      return [] unless defined? @filter_group
      return @filter_group.keys
    end

    # This method clears the filter list and installs the identity filter
    def clear_filters
      @filters ||= {}
      @filters.clear

      @filter_group ||= {}
      @filter_group.clear

      register_filter(:identity) { |stream| stream }
    end

    module Plugins
      class BotModule
        # read accessor for the default filter group for this BotModule
        def filter_group
          @filter_group ||= name
        end

        # write accessor for the default filter group for this BotModule
        def filter_group=(name)
          @filter_group = name
        end

        # define a filter defaulting to the default filter group
        # for this BotModule
        def define_filter(filter, &block)
          @bot.register_filter(filter, self.filter_group, &block)
        end

        # load filters associated with the BotModule by looking in
        # the path(s) specified by the :path option, defaulting to
        # * Config::datadir/filters/<name>.rb
        # * botclass/filters/<name>.rb
        # (note that as <name> we use #dirname() rather than #name(),
        # since we're looking for datafiles; this is only relevant
        # for the very few plugins whose dirname differs from name)
        def load_filters(options={})
          case options[:path]
          when nil
            file = "#{self.dirname}.rb"
            paths = [
              File.join(Config::datadir, 'filters', file),
              @bot.path('filters', file)
            ]
          when Array
            paths = options[:path]
          else
            paths = [options[:path]]
          end

          paths.each do |file|
            instance_eval(File.read(file), file) if File.exist?(file)
          end
        end
      end
    end

  end
end


