require 'helper'
require 'timecop'

class FlowCounterOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  def teardown
    Fluent::Clock.return
    Timecop.return
  end

  CONFIG = %[
unit day
aggregate tag
tag  flowcount
input_tag_remove_prefix test
count_keys message
  ]

  def create_driver(conf=CONFIG)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::FlowCounterOutput).configure(conf)
  end

  def test_configure
    d = create_driver('')
    assert !(d.instance.instance_eval{ @count_bytes })

    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        count_keys message,message2
        unit week
      ]
    }
    d = create_driver %[
      count_keys message
    ]
    assert_equal :minute, d.instance.unit
    assert_equal 60, d.instance.tick
    assert_equal :tag, d.instance.aggregate
    assert_equal :joined, d.instance.output_style
    assert_equal 'flowcount', d.instance.tag
    assert_nil d.instance.input_tag_remove_prefix
    assert_equal ['message'], d.instance.count_keys

    d = create_driver %[
      count_keys field1,field2
    ]
    assert_equal :minute, d.instance.unit
    assert_equal 60, d.instance.tick
    assert_equal :tag, d.instance.aggregate
    assert_equal :joined, d.instance.output_style
    assert_equal 'flowcount', d.instance.tag
    assert_nil d.instance.input_tag_remove_prefix
    assert_equal ['field1', 'field2'], d.instance.count_keys

    d = create_driver %[
      unit second
      count_keys message
    ]
    assert_equal :second, d.instance.unit
    assert_equal 1, d.instance.tick
    assert_equal :tag, d.instance.aggregate
    assert_equal :joined, d.instance.output_style
    assert_equal 'flowcount', d.instance.tag
    assert_nil d.instance.input_tag_remove_prefix
    assert_equal ['message'], d.instance.count_keys

    d = create_driver %[
      unit hour
      count_keys message
    ]
    assert_equal :hour, d.instance.unit
    assert_equal 3600, d.instance.tick
    assert_equal :tag, d.instance.aggregate
    assert_equal :joined, d.instance.output_style
    assert_equal 'flowcount', d.instance.tag
    assert_nil d.instance.input_tag_remove_prefix
    assert_equal ['message'], d.instance.count_keys

    d = create_driver %[
      output_style tagged
      count_keys message
    ]
    assert_equal :minute, d.instance.unit
    assert_equal 60, d.instance.tick
    assert_equal :tag, d.instance.aggregate
    assert_equal :tagged, d.instance.output_style
    assert_equal 'flowcount', d.instance.tag
    assert_nil d.instance.input_tag_remove_prefix
    assert_equal ['message'], d.instance.count_keys

    d = create_driver %[
      output_style tagged
      count_keys f1, f2, f3
    ]
    assert_equal :minute, d.instance.unit
    assert_equal 60, d.instance.tick
    assert_equal :tag, d.instance.aggregate
    assert_equal :tagged, d.instance.output_style
    assert_equal 'flowcount', d.instance.tag
    assert_nil d.instance.input_tag_remove_prefix
    assert_equal ['f1', 'f2', 'f3'], d.instance.count_keys

    d = create_driver %[
      unit day
      aggregate all
      tag test.flowcount
      input_tag_remove_prefix test
      count_keys message
    ]
    assert_equal :day, d.instance.unit
    assert_equal 86400, d.instance.tick
    assert_equal :all, d.instance.aggregate
    assert_equal :joined, d.instance.output_style
    assert_equal 'test.flowcount', d.instance.tag
    assert_equal 'test', d.instance.input_tag_remove_prefix
    assert_equal ['message'], d.instance.count_keys

    d = create_driver %[
      unit day
      aggregate all
      tag test.flowcount
      input_tag_remove_prefix test
      count_keys *
    ]
    assert_equal :day, d.instance.unit
    assert_equal 86400, d.instance.tick
    assert_equal :all, d.instance.aggregate
    assert_equal :joined, d.instance.output_style
    assert_equal 'test.flowcount', d.instance.tag
    assert_equal 'test', d.instance.input_tag_remove_prefix
    assert d.instance.count_all
  end

  def test_count_initialized
    d = create_driver %[
      aggregate all
      count_keys f1,f2,f3
    ]
    assert_equal 0, d.instance.counts['count']
    assert_equal 0, d.instance.counts['bytes']
  end

  def test_countup
    d = create_driver
    assert_nil d.instance.counts['message_count']
    assert_nil d.instance.counts['message_bytes']

    d.instance.countup('message', 30, 50)
    assert_equal 30, d.instance.counts['message_count']
    assert_equal 50, d.instance.counts['message_bytes']

    d.instance.countup('message', 10, 70)
    assert_equal 40, d.instance.counts['message_count']
    assert_equal 120, d.instance.counts['message_bytes']

    d = create_driver %[
      aggregate all
      count_keys message,field
    ]
    assert_equal 0, d.instance.counts['count']
    assert_equal 0, d.instance.counts['bytes']

    d.instance.countup('message', 30, 50)
    assert_equal 30, d.instance.counts['count']
    assert_equal 50, d.instance.counts['bytes']

    d.instance.countup('field', 10, 70)
    assert_equal 40, d.instance.counts['count']
    assert_equal 120, d.instance.counts['bytes']
  end

  def test_generate_output
    d = create_driver %[
       unit minute
       count_keys message
    ]
    r1 = d.instance.generate_output({'count' => 600, 'bytes' => 18000}, 60)
    assert_equal 10.00, r1['count_rate']
    assert_equal 300.00, r1['bytes_rate']
    r2 = d.instance.generate_output({'count' => 100, 'bytes' => 1000}, 60)
    assert_equal 1.66, r2['count_rate']
    assert_equal 16.66, r2['bytes_rate']

    d = create_driver %[
      unit hour
      count_keys f1,f2
    ]
    r3 = d.instance.generate_output({'xx_count' => 1800, 'xx_bytes' => 600000}, 3600)
    assert_equal 0.50, r3['xx_count_rate']
    assert_equal 166.66, r3['xx_bytes_rate']

    r4 = d.instance.generate_output({'t1_count' => 7200, 't1_bytes' => 14400, 't2_count' => 14400, 't2_bytes' => 288000}, 3600)
    assert_equal 2.00, r4['t1_count_rate']
    assert_equal 4.00, r4['t1_bytes_rate']
    assert_equal 4.00, r4['t2_count_rate']
    assert_equal 80.00, r4['t2_bytes_rate']
  end

  def test_emit
    d1 = create_driver(CONFIG)
    time = Time.parse("2012-01-02 13:14:15").to_i
    d1.run(default_tag: 'test.tag1') do
      3600.times do
        d1.feed(time, {'message'=> 'a' * 100})
        d1.feed(time, {'message'=> 'b' * 100})
        d1.feed(time, {'message'=> 'c' * 100})
      end
    end
    r1 = d1.instance.flush(3600 * 24)
    assert_equal 3600*3, r1['tag1_count']
    assert_equal 3600*3*100, r1['tag1_bytes']
    assert_equal (300/24.0).floor / 100.0, r1['tag1_count_rate'] # 3 * 3600 / (60 * 60 * 24) as xx.xx
    assert_equal (30000/24.0).floor / 100.0, r1['tag1_bytes_rate'] # 300 * 3600 / (60 * 60 * 24) xx.xx

    d3 = create_driver( %[
      unit minute
      aggregate all
      tag flow
      count_keys f1,f2,f3
    ])
    time = Time.parse("2012-01-02 13:14:15").to_i
    d3.run(default_tag: 'test.tag1') do
      60.times do
        d3.feed({'f1'=>'1'*10, 'f2'=>'2'*20, 'f3'=>'3'*10})
      end
    end
    r3 = d3.instance.flush(60)
    assert_equal 60, r3['count']
    assert_equal 60*40, r3['bytes']
    assert_equal 1.0, r3['count_rate']
    assert_equal 40.0, r3['bytes_rate']
  end

  def test_emit2
    d2 = create_driver( %[
      unit minute
      aggregate all
      tag  flowcount
      input_tag_remove_prefix test
      count_keys f1,f2,f3
    ])
    time = Time.now.to_i
    d2.run(default_tag: 'test.tag2') do
      60.times do
        d2.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d2.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d2.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d2.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d2.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
      end
      d2.instance.flush_emit(Fluent::EventTime.now, 60)
    end
    events = d2.events
    assert_equal 1, events.length
    data = events[0]
    assert_equal 'flowcount', data[0] # tag
    assert_equal 60*5, data[2]['count']
    assert_equal 60*5*20, data[2]['bytes']
  end

  def test_emit3
    d3 = create_driver( %[
      unit minute
      aggregate all
      tag  flowcount
      input_tag_remove_prefix test
      count_keys *
    ])
    time = Time.now.to_i
    d3.run(default_tag: 'test.tag3') do
      60.times do
        d3.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d3.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d3.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d3.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d3.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
      end
      d3.instance.flush_emit(Fluent::EventTime.now, 60)
    end
    events = d3.events
    assert_equal 1, events.length
    data = events[0]
    assert_equal 'flowcount', data[0] # tag
    assert_equal 60*5, data[2]['count']
    msgpack_size = {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'}.to_msgpack.bytesize * 5 * 60
    assert_equal msgpack_size, data[2]['bytes']
  end

  def test_emit_tagged
    d1 = create_driver( %[
      unit minute
      aggregate tag
      output_style tagged
      tag flow
      input_tag_remove_prefix test
      count_keys *
    ])
    time = Time.parse("2012-01-02 13:14:15").to_i
    d1.run(default_tag: 'test.tag1') do
      60.times do
        d1.feed(time, {'message'=> 'hello'})
      end
    end
    r1 = d1.instance.tagged_flush(60)
    assert_equal 1, r1.length
    assert_equal 'tag1', r1[0]['tag']
    assert_equal 60, r1[0]['count']
    assert_equal 60*15, r1[0]['bytes']
    assert_equal 1.0, r1[0]['count_rate']
    assert_equal 15.0, r1[0]['bytes_rate']
  end

  def test_emit_not_to_count_bytes
    d1 = create_driver( %[
      unit day
      aggregate tag
      tag  flowcount
      input_tag_remove_prefix test
    ])
    time = Time.parse("2012-01-02 13:14:15").to_i
    r1 = {}
    d1.run(default_tag: 'test.tag1') do
      3600.times do
        d1.feed(time, {'message'=> 'a' * 100})
        d1.feed(time, {'message'=> 'b' * 100})
        d1.feed(time, {'message'=> 'c' * 100})
      end
      r1 = d1.instance.flush(3600 * 24)
    end
    assert_equal 3600*3, r1['tag1_count']
    assert_nil r1['tag1_bytes']
    assert_equal (300/24.0).floor / 100.0, r1['tag1_count_rate'] # 3 * 3600 / (60 * 60 * 24) as xx.xx
    assert_nil r1['tag1_bytes_rate']

    d3 = create_driver( %[
      unit minute
      aggregate all
      tag flow
    ])
    time = Time.parse("2012-01-02 13:14:15").to_i
    d3.run(default_tag: 'test.tag1') do
      60.times do
        d3.feed({'f1'=>'1'*10, 'f2'=>'2'*20, 'f3'=>'3'*10})
      end
    end
    r3 = d3.instance.flush(60)
    assert_equal 60, r3['count']
    assert_nil r3['bytes']
    assert_equal 1.0, r3['count_rate']
    assert_nil r3['bytes_rate']
  end

  def test_emit_records_without_specified_field
    d3 = create_driver( %[
      unit minute
      aggregate all
      tag  flowcount
      input_tag_remove_prefix test
      count_keys f4
    ])
    time = Time.now.to_i
    d3.run(default_tag: 'test.tag4', expect_emits: 1) do
      60.times do
        d3.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d3.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d3.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d3.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
        d3.feed(time, {'f1' => 'abcde', 'f2' => 'vwxyz', 'f3' => '0123456789'})
      end
      d3.instance.flush_emit(Fluent::EventTime.now, 60)
    end
    events = d3.events
    assert_equal 1, events.length
    data = events[0]
    assert_equal 'flowcount', data[0]
    assert_equal 60*5, data[2]['count']
    assert_equal 0, data[2]['bytes']
  end

  data(
    minute: ["minute", 59, 61, 90, 100, 110, 122],
    hour: ["hour", 3500, 3601, 3800, 6900, 7180, 7202],
    day: ["day", 86350, 86401, 86400+20000, 86400+65000, 86400+86350, 86400+86402],
  )
  test 'emit timing' do |data|
    unit, time1, time2, time3, time4, time5, time6 = data

    d = create_driver %[
      unit #{unit}
      timestamp_counting false
      aggregate all
      tag flowcount
      count_keys message
    ]

    start = Fluent::Clock.now
    Fluent::Clock.freeze(start)

    first_emit_before = nil
    first_emit_after = nil
    second_emit_before = nil
    second_emit_after = nil

    prev_emit_count = 0
    wait_next_emit = ->{
      waiting(10) do
        sleep 0.1 while d.emit_count == prev_emit_count
        prev_emit_count = d.emit_count
      end
    }

    d.run(default_tag: 'test', timeout: 300_000) do
      3600.times do
        d.feed({'message'=> 'a' * 100})
        d.feed({'message'=> 'b' * 100})
        d.feed({'message'=> 'c' * 100})
      end

      Fluent::Clock.freeze(start + time1)
      sleep 2 # nothing emitted here - clock is frozen
      assert_equal 0, d.emit_count

      3600.times do
        d.feed({'message'=> 'a' * 100})
        d.feed({'message'=> 'b' * 100})
        d.feed({'message'=> 'c' * 100})
      end

      first_emit_before = Fluent::EventTime.now
      Fluent::Clock.freeze(start + time2)
      wait_next_emit.call # emitted from 7200 * 3 events
      first_emit_after = Fluent::EventTime.now

      Fluent::Clock.freeze(start + time3)

      3600.times do
        d.feed({'message'=> 'a' * 100})
        d.feed({'message'=> 'b' * 100})
        d.feed({'message'=> 'c' * 100})
      end

      Fluent::Clock.freeze(start + time4)
      sleep 1
      assert_equal prev_emit_count, d.emit_count

      Fluent::Clock.freeze(start + time5)
      sleep 1
      assert_equal prev_emit_count, d.emit_count

      second_emit_before = Fluent::EventTime.now
      Fluent::Clock.freeze(start + time6)
      wait_next_emit.call # emitted from 3600 events
      second_emit_after = Fluent::EventTime.now
    end

    events = d.events
    assert_equal 2, events.size
    tag, t1, r1 = events[0]
    assert{ t1 >= first_emit_before }
    assert{ t1 <= first_emit_after }
    assert_equal 3600*3*2, r1["count"]
    tag, t2, r2 = events[1]
    assert{ t2 >= second_emit_before }
    assert{ t2 <= second_emit_after }
    assert_equal 3600*3, r2["count"]
  end

  data(
    minute: [
      "minute",
      "",
      Time.utc(2017,7,26,13,49, 3),
      Time.utc(2017,7,26,13,49,55),
      Time.utc(2017,7,26,13,50, 0),
      Time.utc(2017,7,26,13,50, 3),
      Time.utc(2017,7,26,13,50,49),
      Time.utc(2017,7,26,13,51, 0)],
    hour: [
      "hour",
      "",
      Time.utc(2017,7,26,13,49, 3),
      Time.utc(2017,7,26,13,59,58),
      Time.utc(2017,7,26,14, 0, 0),
      Time.utc(2017,7,26,14,15,49),
      Time.utc(2017,7,26,14,58, 0),
      Time.utc(2017,7,26,15, 0, 0)],
    day: [
      "day",
      "timestamp_timezone +0000",
      Time.utc(2017,7,26,13,49, 3),
      Time.utc(2017,7,26,23,59,58),
      Time.utc(2017,7,27, 0, 0, 0),
      Time.utc(2017,7,27, 1,30,10),
      Time.utc(2017,7,27,23,38,50),
      Time.utc(2017,7,28, 0, 0, 0)],
    dayz: [
      "day",
      "timestamp_timezone -0700",
      Time.new(2017,7,26,13,49, 3, "-07:00"),
      Time.new(2017,7,26,23,59,58, "-07:00"),
      Time.new(2017,7,27, 0, 0, 0, "-07:00"),
      Time.new(2017,7,27, 1,30,10, "-07:00"),
      Time.new(2017,7,27,23,38,50, "-07:00"),
      Time.new(2017,7,28, 0, 0, 0, "-07:00")],
  )
  test 'emit timing with timestamp_counting' do |data|
    unit, conf, start, time1, time2, time3, time4, time5 = data

    d = create_driver %[
      unit #{unit}
      timestamp_counting true
      #{conf}
      aggregate all
      tag flowcount
      count_keys message
    ]

    Timecop.freeze(start)

    prev_emit_count = 0
    wait_next_emit = ->{
      waiting(10) do
        sleep 0.1 while d.emit_count == prev_emit_count
        prev_emit_count = d.emit_count
      end
    }

    d.run(default_tag: 'test', timeout: 300_000) do
      3600.times do
        d.feed({'message'=> 'a' * 100})
        d.feed({'message'=> 'b' * 100})
        d.feed({'message'=> 'c' * 100})
      end

      Timecop.freeze(time1)
      sleep 2 # nothing emitted here - time is frozen
      assert_equal 0, d.emit_count

      3600.times do
        d.feed({'message'=> 'a' * 100})
        d.feed({'message'=> 'b' * 100})
        d.feed({'message'=> 'c' * 100})
      end

      Timecop.freeze(time2)
      wait_next_emit.call # emitted from 7200 * 3 events

      Timecop.freeze(time3)

      3600.times do
        d.feed({'message'=> 'a' * 100})
        d.feed({'message'=> 'b' * 100})
        d.feed({'message'=> 'c' * 100})
      end

      Timecop.freeze(time4)
      sleep 1
      assert_equal prev_emit_count, d.emit_count

      Timecop.freeze(time5)
      wait_next_emit.call # emitted from 3600 events
    end

    events = d.events
    assert_equal 2, events.size
    tag, t1, r1 = events[0]
    assert_equal Fluent::EventTime.new(time2.to_i, 0), t1
    assert_equal 3600*3*2, r1["count"]
    tag, t2, r2 = events[1]
    assert_equal Fluent::EventTime.new(time5.to_i, 0), t2
    assert_equal 3600*3, r2["count"]
  end
end
