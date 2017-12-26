require 'fluent/plugin/output'
require 'fluent/clock'
require 'time'

class Fluent::Plugin::FlowCounterOutput < Fluent::Plugin::Output
  Fluent::Plugin.register_output('flowcounter', self)

  helpers :event_emitter, :timer

  config_param :unit, :enum, list: [:second, :minute, :hour, :day], default: :minute
  config_param :timestamp_counting, :bool, default: false
  config_param :timestamp_timezone, :string, default: nil
  config_param :aggregate, :enum, list: [:tag, :all], default: :tag
  config_param :output_style, :enum, list: [:joined, :tagged], default: :joined
  config_param :tag, :string, default: 'flowcount'
  config_param :input_tag_remove_prefix, :string, default: nil
  config_param :count_keys, :array, value_type: :string, default: []
  config_param :delimiter, :string, default: '_'
  config_param :delete_idle, :bool, default: false

  attr_accessor :counts
  attr_accessor :last_checked
  attr_accessor :count_all
  attr_reader :tick

  def configure(conf)
    super

    @tick = case @unit
            when :second then 1
            when :minute then 60
            when :hour then 3600
            when :day then 86400
            else
              raise Fluent::ConfigError, "flowcounter unit allows second/minute/hour/day"
            end
    if @output_style == :tagged and @aggregate != :tag
      raise Fluent::ConfigError, "flowcounter aggregate must be 'tag' when output_style is 'tagged'"
    end
    if @input_tag_remove_prefix
      @removed_prefix_string = @input_tag_remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end
    @count_all = false
    if @count_keys && !@count_keys.empty?
      @count_all = (@count_keys == ['*'])
      @count_bytes = true
    else
      @count_bytes = false
    end

    if @timestamp_counting
      @timestamp_timezone_offset = 0
      if @unit == :second
        raise Fluent::ConfigError, "timestamp_counting cannot be enabled with unit: second"
      elsif @unit == :day
        unless @timestamp_timezone
          raise Fluent::ConfigError, "timestamp_counting requires timestamp_timezone to be configured (e.g., '-0700') if unit is day"
        end
        @timestamp_timezone_offset = Time.zone_offset(@timestamp_timezone)
        unless @timestamp_timezone_offset
          raise Fluent::ConfigError, "invalid timestamp_timezone value (specify like '-0700')"
        end
      end
      @last_checked = nil
      @initializer = ->{ now = Fluent::EventTime.now.to_i; @last_checked = now - (now % @tick) - @timestamp_timezone_offset }
      @checker = ->{ Fluent::EventTime.now.to_i - @last_checked >= @tick }
      @updater = ->{ @last_checked += @tick; return Fluent::EventTime.new(@last_checked, 0), @tick }
    else
      @last_checked = nil
      @initializer = ->{ @last_checked = Fluent::Clock.now }
      @checker = ->{ Fluent::Clock.now - @last_checked >= @tick }
      @updater = ->{ prev = @last_checked; @last_checked = Fluent::Clock.now; return Fluent::EventTime.now, @last_checked - prev }
    end

    @counts = count_initialized
    @mutex = Mutex.new
  end

  def multi_workers_ready?
    true
  end

  def start
    super

    @initializer.call
    timer_execute(:out_flowcounter_watcher, 0.5) do
      if @checker.call
        now, interval = @updater.call
        flush_emit(now, interval)
      end
    end
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
    keys = delete_idle ? nil : @counts.keys
    flushed,@counts = @counts,count_initialized(keys)
    generate_output(flushed, step)
  end

  def tagged_flush(step)
    keys = delete_idle ? nil : @counts.keys
    flushed,@counts = @counts,count_initialized(keys)
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

  def flush_emit(now, step)
    if @output_style == :tagged
      tagged_flush(step).each do |data|
        router.emit(@tag, now, data)
      end
    else
      router.emit(@tag, now, flush(step))
    end
  end

  FOR_MISSING = ''

  def process(tag, es)
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
  end
end
