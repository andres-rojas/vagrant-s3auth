require 'aws'
require 'log4r'
require 'net/http'
require 'uri'

module VagrantPlugins
  module S3Auth
    module Util
      S3_HOST_MATCHER = /^((?<bucket>[[:alnum:]\-\.]+).)?s3([[:alnum:]\-\.]+)?\.amazonaws\.com$/

      LOCATION_TO_REGION = Hash.new { |_, key| key }.merge(
        nil => 'us-east-1',
        'EU' => 'eu-west-1'
      )

      def self.s3_object_for(url, follow_redirect = true)
        url = URI(url)

        if url.scheme == 's3'
          bucket = url.host
          key = url.path[1..-1]
          raise Errors::MalformedShorthandURLError, url: url unless bucket && key
        elsif match = S3_HOST_MATCHER.match(url.host)
          components = url.path.split('/').delete_if(&:empty?)
          bucket = match['bucket'] || components.shift
          key = components.join('/')
        end

        if bucket && key
          AWS::S3.new(region: get_bucket_region(bucket))
            .buckets[bucket].objects[key]
        elsif follow_redirect
          response = Net::HTTP.get_response(url) rescue nil
          if response.is_a?(Net::HTTPRedirection)
            s3_object_for(response['location'], false)
          end
        end
      end

      def self.s3_url_for(method, s3_object)
        s3_object.url_for(method,
          expires: 10,
          signature_version: :v4,
          force_path_style: true)
      end

      def self.get_bucket_region(bucket)
        LOCATION_TO_REGION[AWS::S3.new.buckets[bucket].location_constraint]
      rescue AWS::S3::Errors::AccessDenied
        raise Errors::BucketLocationAccessDeniedError,
          bucket: bucket,
          access_key: ENV['AWS_ACCESS_KEY_ID']
      end
    end
  end
end
