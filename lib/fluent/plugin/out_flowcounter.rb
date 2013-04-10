require 'fluent/mixin/config_placeholders'

class Fluent::FlowCounterOutput < Fluent::Output
  Fluent::Plugin.register_output('flowcounter', self)

  config_param :unit, :string, :default => 'minute'
  config_param :aggregate, :string, :default => 'tag'
  config_param :tag, :string, :default => 'flowcount'
  config_param :input_tag_remove_prefix, :string, :default => nil
  config_param :count_keys, :string

  include Fluent::Mixin::ConfigPlaceholders

  attr_accessor :counts
  attr_accessor :last_checked
  attr_accessor :count_all

  def configure(conf)
    super

    @unit = case @unit
            when 'minute' then :minute
            when 'hour' then :hour
            when 'day' then :day
            else
              raise Fluent::ConfigError, "flowcounter unit allows minute/hour/day"
            end
    @aggregate = case @aggregate
                 when 'tag' then :tag
                 when 'all' then :all
                 else
                   raise Fluent::ConfigError, "flowcounter aggregate allows tag/all"
                 end
    if @input_tag_remove_prefix
      @removed_prefix_string = @input_tag_remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end
    @count_keys = @count_keys.split(',')
    @count_all = (@count_keys == ['*'])

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
      {'count' => 0, 'bytes' => 0}
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
      c = name + '_count'
      b = name + '_bytes'
    end
    @mutex.synchronize {
      @counts[c] = (@counts[c] || 0) + counts
      @counts[b] = (@counts[b] || 0) + bytes
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

  def flush_emit(step)
    Fluent::Engine.emit(@tag, Fluent::Engine.now, flush(step))
  end

  def start_watch
    # for internal, or tests only
    @watcher = Thread.new(&method(:watch))
  end

  def watch
    # instance variable, and public accessable, for test
    @last_checked = Fluent::Engine.now
    tick = case @unit
           when :minute then 60
           when :hour then 3600
           when :day then 86400
           else
             raise RuntimeError, "@unit must be one of minute/hour/day"
           end
    while true
      sleep 0.5
      if Fluent::Engine.now - @last_checked >= tick
        now = Fluent::Engine.now
        flush_emit(now - @last_checked)
        @last_checked = now
      end
    end
  end

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
        b += record.to_msgpack.bytesize
      }
    else
      es.each {|time,record|
        c += 1
        b += @count_keys.inject(0){|s,k| s + record[k].bytesize}
      }
    end
    countup(name, c, b)

    chain.next
  end
end
