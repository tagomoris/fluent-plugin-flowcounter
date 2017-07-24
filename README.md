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

Counts from fields 'field1' and 'field2', per minute(default), aggregates per tags(default), output with tag 'flowcount'(default).

    <match **>
      @type copy
      <store>
        # original output configurations...
      </store>
      <store>
        @type flowcounter
        count_keys field1,field2
      </store>
    </match>
    
    <match flowcount>
      # output configurations where to send count results
    </match>

Counts from field 'message', per hour, aggregates all tags, output with tag 'fluentd.traffic'.

    <match **>
      @type copy
      <store>
        # original output configurations...
      </store>
      <store>
        @type flowcounter
        count_keys message
        unit       hour
        aggregate  all
        tag        fluentd.traffic
      </store>
    </match>
    
    <match fluentd.traffic>
      # output configurations where to send count results
    </match>

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

Use '${hostname}' if you want your hostname in tag.

    <match target.**>
      @type flowcounter
      count_keys *
      tag fluentd.node.${hostname}
    </match>

Counts active tag, stop count records if the tag message stoped(when aggragates per tag).

    <match target.**>
      @type flowcounter
      count_keys *
      aggregate tag
      delete_idle true
    </match>

Set `use_clock_output` to `true`(default is `false`) and set `clock_output_interval`(support `minutely`|`hourly`|`daily`, default is `minutely`) when using clock output format.

    <match target.**>
      @type flowcounter
      count_keys *
      aggregate tag
      use_clock_output true
      clock_output_interval daily
    </match>

## TODO

* consider what to do next
* patches welcome!

## Copyright

* Copyright
  * Copyright (c) 2012- TAGOMORI Satoshi (tagomoris)
* License
  * Apache License, Version 2.0
