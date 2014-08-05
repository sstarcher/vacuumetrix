#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(__FILE__), *%w[.. conf])
$:.unshift File.join(File.dirname(__FILE__), *%w[.. lib])

require 'config'
require 'Sendit'
require 'rubygems' if RUBY_VERSION < "1.9"
require 'fog'
require 'optparse'
require 'set'

begin
  require 'system_timer'
  SomeTimer = SystemTimer
rescue LoadError
  require 'timeout'
  SomeTimer = Timeout
end

# Start back 15m by default
#  Instances with detailed monitoring will generally have 10+ metrics for this offset
#  Instances w/o detailed monitoring will only have 1-2
# Adjust for your environment
options = {
  :start_offset => 900,
  :end_offset   => 0
}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: AWScloudwatchEC2.rb [options]"

  opts.on('-s', '--start-offset [OFFSET_SECONDS]', 'Time in seconds to offset from current time as the start of the metrics period. Default 900 (15m)') do |s|
    options[:start_offset] = s
  end

  opts.on('-e', '--end-offset [OFFSET_SECONDS]', 'Time in seconds to offset from current time as the end of the metrics period. Default 0 (now)') do |e|
    options[:end_offset] = e
  end

  opts.on('-h', '--help', '') do
    puts opts
    exit
  end
end

optparse.parse!

startTime = Time.now.utc - options[:start_offset].to_i
endTime   = Time.now.utc - options[:end_offset].to_i


cloudwatch  = Fog::AWS::CloudWatch.new(
  :aws_access_key_id => $awsaccesskey,
:aws_secret_access_key => $awssecretkey)


metrics = [
  {
    :name => "CPUUtilization",
    :unit => "Percent",
    :stat => "Average"
  }
]

counter=0
namespaces = ['RDS','EC2Instance','LH/ChannelPayloadListingDetail','LH/ChannelRunnerStats','LH/CreateEnterpriseClientList','LH/CreateJobPostings',
              'LH/CreateMlsList',
              'LH/CreatePackageOptionsList',
              'LH/CreatePublisherList',
              'LH/Databases',
              'LH/GoogleWebmasterStats',
              'LH/InventoryChannel',
              'LH/JSMetrics',
              'LH/ListingMatcher',
              'LH/ListingStatusSellerReport',
              'LH/MetricsHiveMigrationTool',
              'LH/MoveSyndicationFeed',
              'LH/MoveSyndicationSync',
              'LH/PhotoProxy',
              'LH/RenParticipantStats',
              'LH/Reports',
              'LH/StatusServlet',
              'LH/Webservers',
              'ScriptRunSuccess', 'ScriptMetrics']
for namespace in namespaces
  options = {'Namespace'=> namespace}
  next_metrics = cloudwatch.list_metrics(options)
  metrics = next_metrics.body['ListMetricsResult']['Metrics']
  next_token = next_metrics.body['ListMetricsResult']['NextToken']
  until next_token.nil?
    next_token = next_metrics.body['ListMetricsResult']['NextToken']

    options['NextToken'] = next_token
    next_metrics = cloudwatch.list_metrics(options)
    metrics += next_metrics.body['ListMetricsResult']['Metrics']
    puts metrics.length
  end


  namespaces = SortedSet.new

  for value in metrics
    namespaces.add(value['Namespace'])
    counter+=value['Dimensions'].length
  end
end

puts "Dims: #{counter}"
puts namespaces.length()

exit
count=0
metrics.each do |metric|
  puts count
  count+=1
  responses = cloudwatch.get_metric_statistics({
                                                 'Statistics' => 'Average',
                                                 'StartTime'  => startTime.iso8601,
                                                 'EndTime'    => endTime.iso8601,
                                                 'Period'     => 60,
                                                 'Unit'       => 'Count',
                                                 'MetricName' => metric['MetricName'],
                                                 'Namespace'  => metric['Namespace'],
                                                 'Dimensions' => metric['Dimensions']
  }).body['GetMetricStatisticsResult']['Datapoints']

  responses.each do |response|
    metricpath = "AWScloudwatch.Custom." + namespace + "." + metric[:name]
    begin
      metricvalue     = response[metric[:stat]]
      metrictimestamp = response["Timestamp"].to_i.to_s
      Sendit metricpath, metricvalue, metrictimestamp
    rescue
      # ignored
    end
  end

end
