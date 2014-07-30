#!/usr/bin/env ruby
## grab metrics from AWS cloudwatch
### David Lutz
### 2012-07-15
### gem install fog  --no-ri --no-rdoc

$:.unshift File.join(File.dirname(__FILE__), *%w[.. conf])
$:.unshift File.join(File.dirname(__FILE__), *%w[.. lib])

require 'config'
require 'Sendit'
require 'rubygems' if RUBY_VERSION < "1.9"
require 'fog'
require 'json'
require 'optparse'

options = {
  :start_offset => 600,
  :end_offset => 0
}

optparse = OptionParser.new do|opts|
  opts.banner = "Usage: AWScloudwatchELB.rb [options]"

  opts.on( '-s', '--start-offset [OFFSET_SECONDS]', 'Time in seconds to offset from current time as the start of the metrics period. Default 180') do |s|
    options[:start_offset] = s
  end

  opts.on( '-e', '--end-offset [OFFSET_SECONDS]', 'Time in seconds to offset from current time as the start of the metrics period. Default 120') do |e|
    options[:end_offset] = e
  end

  # This displays the help screen, all programs are
  # assumed to have this option.
  opts.on( '-h', '--help', '' ) do
    puts opts
    exit
  end


end

optparse.parse!


sqs = Fog::AWS::SQS.new(:aws_secret_access_key => $awssecretkey, :aws_access_key_id => $awsaccesskey, :region => $awsregion)

queues = []
for queue in sqs.list_queues().body['QueueUrls']
  queues << queue.split('/')[-1]
end


startTime = Time.now.utc - options[:start_offset].to_i
endTime  = Time.now.utc - options[:end_offset].to_i


metricNames = {"ApproximateNumberOfMessagesDelayed" => "Average",
               "ApproximateNumberOfMessagesNotVisible" => "Average",
               "ApproximateNumberOfMessagesVisible" => "Average",
               "NumberOfEmptyReceives" => "Sum",
               "NumberOfMessagesDeleted" => "Sum",
               "NumberOfMessagesReceived" => "Sum",
               "NumberOfMessagesSent" => "Sum"
               }

unit = 'Count'

cloudwatch = Fog::AWS::CloudWatch.new(:aws_secret_access_key => $awssecretkey, :aws_access_key_id => $awsaccesskey, :region => $awsregion)

queues.each do |table|
  metricNames.each do |metricName, statistic|
    responses = cloudwatch.get_metric_statistics({
                                                   'Statistics' => statistic,
                                                   'StartTime' => startTime.iso8601,
                                                   'EndTime' => endTime.iso8601,
                                                   'Period' => 600,
                                                   'Unit' => unit,
                                                   'MetricName' => metricName,
                                                   'Namespace' => 'AWS/SQS',
                                                   'Dimensions' => [{
                                                                      'Name' => 'QueueName',
                                                                      'Value' => table
                                                   }]
    })

    responses.body['GetMetricStatisticsResult']['Datapoints'].each do |response|
      metricpath = "AWScloudwatch.SQS." + table + "." + metricName
      begin
        metricvalue = response[statistic]
        metrictimestamp = response["Timestamp"].to_i.to_s
      rescue
        metricvalue = 0
        metrictimestamp = endTime.to_i.to_s
      end

      Sendit metricpath, metricvalue, metrictimestamp
    end
  end

end
