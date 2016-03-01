require 'fluent/mixin/config_placeholders'

class Fluent::FlowCounterOutput < Fluent::Output
  Fluent::Plugin.register_output('flowcounter', self)

  # Define `log` method for v0.10.42 or earlier
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  # Define `router` method of v0.12 to support v0.10 or earlier
  unless method_defined?(:router)
    define_method("router") { ::Fluent::Engine }
  end

  config_param :unit, :string, default: 'minute'
  config_param :aggregate, :string, default: 'tag'
  config_param :output_style, :string, default: 'joined'
  config_param :tag, :string, default: 'flowcount'
  config_param :input_tag_remove_prefix, :string, default: nil
  config_param :count_keys, :string, default: nil
  config_param :delimiter, :string, default: '_'

  include Fluent::Mixin::ConfigPlaceholders

  attr_accessor :counts
  attr_accessor :last_checked
  attr_accessor :count_all
  attr_reader :tick

  def configure(conf)
    super

    @unit = case @unit
            when 'second' then :second
            when 'minute' then :minute
            when 'hour' then :hour
            when 'day' then :day
            else
              raise Fluent::ConfigError, "flowcounter unit allows second/minute/hour/day"
            end
    @tick = case @unit
            when :second then 1
            when :minute then 60
            when :hour then 3600
            when :day then 86400
            else
              raise Fluent::ConfigError, "flowcounter unit allows second/minute/hour/day"
            end
    @aggregate = case @aggregate
                 when 'tag' then :tag
                 when 'all' then :all
                 else
                   raise Fluent::ConfigError, "flowcounter aggregate allows tag/all"
                 end
    @output_style = case @output_style
                 when 'joined' then :joined
                 when 'tagged' then :tagged
                 else
                   raise Fluent::ConfigError, "flowcounter output_style allows joined/tagged"
                 end
    if @output_style == :tagged and @aggregate != :tag
      raise Fluent::ConfigError, "flowcounter aggregate must be 'tag' when output_style is 'tagged'"
    end
    if @input_tag_remove_prefix
      @removed_prefix_string = @input_tag_remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end
    if @count_keys
      @count_keys = @count_keys.split(',')
      @count_all = (@count_keys == ['*'])
      @count_bytes = true
    else
      @count_bytes = false
    end

    @counts = count_initialized
    @mutex = Mutex.new
  end

  def start
    super
    start_watch
  end

  def shutdown
    super
    @watcher.terminate
    @watcher.join
  end

  def count_initialized(keys=nil)
    if @aggregate == :all
      if @count_bytes
        {'count' => 0, 'bytes' => 0}
      else
        {'count' => 0}
      end
    elsif keys
      values = Array.new(keys.length){|i| 0 }
      Hash[[keys, values].transpose]
    else
      {}
    end
  end

  def countup(name, counts, bytes)
    c = 'count'
    b = 'bytes'
    if @aggregate == :tag
      c = name + delimiter + 'count'
      b = name + delimiter + 'bytes' if @count_bytes
    end
    @mutex.synchronize {
      @counts[c] = (@counts[c] || 0) + counts
      @counts[b] = (@counts[b] || 0) + bytes if @count_bytes
    }
  end

  def generate_output(counts, step)
    rates = {}
    counts.keys.each {|key|
      rates[key + '_rate'] = ((counts[key] * 100.0) / (1.00 * step)).floor / 100.0
    }
    counts.update(rates)
  end

  def flush(step)
    flushed,@counts = @counts,count_initialized(@counts.keys)
    generate_output(flushed, step)
  end

  def tagged_flush(step)
    flushed,@counts = @counts,count_initialized(@counts.keys)
    names = flushed.keys.select {|x| x.end_with?(delimiter + 'count')}.map {|x| x.chomp(delimiter + 'count')}
    names.map {|name|
      counts = {
        'count' => flushed[name + delimiter + 'count'],
      }
      if @count_bytes
        counts['bytes'] = flushed[name + delimiter + 'bytes']
      end
      data = generate_output(counts, step)
      data['tag'] = name
      data
    }
  end

  def flush_emit(step)
    if @output_style == :tagged
      tagged_flush(step).each do |data|
        router.emit(@tag, Fluent::Engine.now, data)
      end
    else
      router.emit(@tag, Fluent::Engine.now, flush(step))
    end
  end

  def start_watch
    # for internal, or tests only
    @watcher = Thread.new(&method(:watch))
  end

  def watch
    # instance variable, and public accessable, for test
    @last_checked = Fluent::Engine.now
    while true
      sleep 0.5
      if Fluent::Engine.now - @last_checked >= @tick
        now = Fluent::Engine.now
        flush_emit(now - @last_checked)
        @last_checked = now
      end
    end
  end

  FOR_MISSING = ''

  def emit(tag, es, chain)
    name = tag
    if @input_tag_remove_prefix and
        ( (tag.start_with?(@removed_prefix_string) and tag.length > @removed_length) or tag == @input_tag_remove_prefix)
      name = tag[@removed_length..-1]
    end
    c,b = 0,0
    if @count_all
      es.each {|time,record|
        c += 1
        b += record.to_msgpack.bytesize if @count_bytes
      }
    else
      es.each {|time,record|
        c += 1
        b += @count_keys.inject(0){|s,k| s + (record[k] || FOR_MISSING).bytesize} if @count_bytes
      }
    end
    countup(name, c, b)

    chain.next
  end
end
