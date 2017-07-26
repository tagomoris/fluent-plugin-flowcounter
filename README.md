# fluent-plugin-flowcounter

Count metrics below about matches. This is a plugin for [Fluentd](http://fluentd.org)

* Messages per second/minute/hour/day
* Bytes per second/minute/hour/day (optional)
* Messages per second (average every second/minute/hour/day)
* Bytes per second (average every second/minute/hour/day) (optional)

FlowCounterOutput emits messages contains results data, so you can output these message (with 'flowcount' tag by default) to any outputs you want.

    output ex1 (aggragates all inputs): {"count":300, "bytes":3660, "count_rate":5, "bytes_rate":61}
    output ex2 (aggragates per tag): {"test_count":300, "test_bytes":3660, "test_count_rate":5, "test_bytes_rate":61, "service1_count":180, "service1_bytes":7260, "service1_count_rate":3, "service1_bytes_rate":121}

Or, output result data with for each tags (with `output_style tagged`)

    {"tag":"test", "count":300, "bytes":3660, "count_rate":5, "bytes_rate":61}
    {"tag":"service1", "count":180, "bytes":7260, "count_rate":3, "bytes_rate":121}

`input_tag_remove_prefix` option available if you want to remove tag prefix from output field names.

If you want to count only records, omit `count_keys` configuration.

    {"tag":"test", "count":300, "count_rate":5}

## Configuration

Counts from fields 'field1' and 'field2', per minute(default), aggregates per tags(default), output with tag 'flowcount'(default). It is strongly recommended to specify `@label` to control event stream routing.

    <match **>
      @type copy
      <store>
        # original output configurations...
      </store>
      <store>
        @type flowcounter
        @label @counts
        count_keys field1,field2
      </store>
    </match>
    
    <label @counts>
      <match flowcount>
        # output configurations where to send count results
      </match>
    </label>

Counts from field 'message', per hour, aggregates all tags, output with tag 'fluentd.traffic'.

    <match **>
      @type copy
      <store>
        # original output configurations...
      </store>
      <store>
        @type flowcounter
        @label @counts
        count_keys message
        unit       hour
        aggregate  all
        tag        fluentd.traffic
      </store>
    </match>
    
    <label @counts>
      <match fluentd.traffic>
        # output configurations where to send count results
      </match>
    </label>

To count with all fields in messages, specify 'count_keys *'.

    <match target.**>
      @type flowcounter
      count_keys *
      unit hour
      aggregate all
      tag fluentd.traffic
    </match>

To count records only (without bytes), omit `count_keys` (it runs in better performance.)

    <match target.**>
      @type flowcounter
      unit hour
      aggregate all
      tag fluentd.traffic
    </match>

Counts active tag, stop count records if the tag message stoped(when aggragates per tag).

    <match target.**>
      @type flowcounter
      count_keys *
      aggregate tag
      delete_idle true
    </match>

### Generate Output at Zero Time

(NOTE: This feature is supported at v1.1.0 or later - only for Fluentd v0.14 or later.)

If you want to generate count results at every 0 second (for unit:minute), at every 00:00 (for unit:hour) or at every 00:00:00 (for unit:day), specify `timestamp_counting true` in your configuration.

    <match target.**>
      @type flowcounter
      count_keys *
      aggregate all
      unit hour
      timestamp_counting true
    </match>

The configuration above emits output at 00:00:00, 01:00:00, 02:00:00, .... every day. In this use case, `unit: day` requires to configure `timestamp_timezone` to set the timezone to determine the beginning of the day.

    <match target.**>
      @type flowcounter
      count_keys *
      aggregate all
      unit day
      timestamp_counting true
      timestamp_timezone -03:00
    </match>

### Embedding Hostname

The current version of this plugin doesn't support `${hostname}` placeholders. Use ruby code embedding for such purpose:

    <match target.**>
      @type flowcounter
      count_keys *
      tag "fluentd.node.#{Socket.gethostname}"
    </match>

See [Fluentd document page](https://docs.fluentd.org/articles/config-file#embedded-ruby-code) for further details.

## TODO

* Support Counter API when it's supported in Fluentd core
* Patches welcome!

## Copyright

* Copyright
  * Copyright (c) 2012- TAGOMORI Satoshi (tagomoris)
* License
  * Apache License, Version 2.0
